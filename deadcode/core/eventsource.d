module deadcode.core.eventsource;

import core.time : MonoTime, Duration, dur;
import std.meta : AliasSeq;
import std.typecons : Tuple;
import std.variant;

import deadcode.core.event;
import deadcode.core.coreevents;

alias EventOutputRange = MainEventSource.OutputRange;

interface ITimer
{
	@property double currTime() const nothrow;
}

class SystemTimer : ITimer
{
	void reset() {}

	@property double currTime() const nothrow
	{
		return currSystemTime;
	}

	static @property double currSystemTime() nothrow
	{
		import std.conv : to;
        static import core.time;

        auto t = MonoTime.currTime;
        auto nsecs = core.time.ticksToNSecs(t.ticks);
        auto res = dur!"nsecs"(nsecs);
		//auto res = t.to!("seconds", double)();
        core.time.TickDuration td = res.to!(core.time.TickDuration)();
		return core.time.to!("seconds", double)(td);
	}
}

/** Contains event sources and lets you listen or wait for events using
	an input range interface.

	All threads can put() events to this source. A specific implementation
	of this abstract class should poll OS for events and this base class will
	take care of waking up the main thread when Events are put from other threads.

	Examples of a class deriving from this class could be 
	SDLMainEventSource or GLFWMainEventSource.
*/
abstract class MainEventSource
{
	import core.thread;
	import core.time;
	import std.exception : enforce;
    
    protected
    {
        shared(TimeoutEvent)[] _pendingTimeouts;

        Event _currentEvent;
        Event _eventBuffer;

        Duration _timeout;
        bool _isListening;
        ThreadID _ownerThreadID;	
        Queue!Event _ownerQueue;    // Events put from the owner queue
        shared RWQueue!Event _threadQueue; // Event put from other threads    
        ITimer _timer;
    }

	@property 
    {
        void timer(ITimer t)
        {
            _timer = t;
        }
        
        ITimer timer()
        {
            return _timer;
        }
    }

    this(ITimer t)
	{
		_timeout = Duration.max;
		_ownerThreadID = Thread.getThis().id;
		_ownerQueue = new typeof(_ownerQueue)(256);
		_isListening = true;
		_currentEvent = null;
		_eventBuffer = null; // Single event for peeking for events to combine
    }

	final @property Duration timeout() const pure nothrow @system @nogc   
	{
		return _timeout;
	}

	final @property void timeout(Duration d)  
	{
		enforce(!d.isNegative);
		_timeout = d;
	}

	final @property bool stopped() @nogc nothrow @safe const 
	{
		return !_isListening;
	}

	final @property void timeout(double d)  
	{
		long nanoSecs = cast(long) (d * 1_000_000_000);
		timeout = dur!"nsecs"(nanoSecs);
	}

	// Stop getting events into the internal event queue and simply let anyone empty the
	// internal event queue if they want.
	void stop() 
	{
		_isListening = false;
	}

	final bool nextWillBlock()
	{
		bool result = false;
		if (!stopped && _currentEvent is null && _eventBuffer is null && ownerQueue.empty && _threadQueue.empty)
		{
			size_t idx;
			Event res = nextTimeoutEvent(idx);
			if (res !is null)
			{
				auto dt = res.timestamp - MonoTime.currTime;
				result = dt > dur!"hnsecs"(0);
			}
			else
			{
				_currentEvent = poll(dur!"hnsecs"(0));
				result = _currentEvent is null;
			}
		}
		return result;
	}

	final @property bool empty() 
	{
		enforce(Thread.getThis().id == _ownerThreadID);
		return _currentEvent is null && stopped;
	}
		
	final @property Event front() 
	{
		enforce(Thread.getThis().id == _ownerThreadID);
		if (_currentEvent is null)
		{
			Event next = _eventBuffer;
			_eventBuffer = null;

			if (next is null)
				next = _front();
			
			immutable allowCombine = next.allowCombine;

			while (allowCombine && !nextWillBlock())
			{
				// _currentEvent may have beem set by nextWillBlock
				_eventBuffer = _currentEvent is null ? _front() : _currentEvent;
				_currentEvent = null;
				if (next.combineIntoThis(_eventBuffer))
				{
					_eventBuffer.dispose();
					_eventBuffer = null;
				}
				else
				{
					break;
				}
			}

			_currentEvent = next;
		}
		return _currentEvent;
	}

	final void popFront() 
	{
		enforce(Thread.getThis().id == _ownerThreadID);
		assert(_currentEvent !is null);
		_currentEvent = null;
	}

	final bool putAsOwnerThreadIfRoom(Event ev) @nogc
	{
		if (stopped)
			return false; 

		// assert(Thread.getThis().id == _ownerThreadID);
		_ownerQueue.enqueueIfRoom(ev);
		return true;
	}

	// owning thread will take over ownership of event
	final bool put(Event ev) 
	{
		if (stopped)
			return false; 

		if (Thread.getThis().id == _ownerThreadID)
		{
			ownerQueue.enqueue(ev);
		}
		else
		{
			_threadQueue.pushBusyWait(cast(shared)ev);
			signalEventQueuedByOtherThread();
		}
		return true;
	}

	struct OutputRange
	{
		private shared(MainEventSource) _eventSource;
		
		private MainEventSource eventSource() @nogc { return cast(MainEventSource) _eventSource; }

		@property bool isValid() const pure @safe nothrow { return _eventSource !is null; }
        
        bool put(Event ev)
		{
			return eventSource.put(ev);
		}

		bool putAsOwnerThreadIfRoom(Event ev) @nogc
		{
			return eventSource.putAsOwnerThreadIfRoom(ev);
		}

		shared(TimeoutEvent) scheduleTimeoutNow(Variant userData = Variant.init)
		{
			return scheduleTimeout(dur!"hnsecs"(0), userData);
		}

		shared(TimeoutEvent) scheduleTimeout(Duration dt, Variant userData = Variant.init)
		{
			return eventSource.scheduleTimeout(dt, userData);
		}

		bool abortTimeout(shared(TimeoutEvent) scheduledTimeoutEvent) 
		{
			return eventSource.abortTimeout(scheduledTimeoutEvent);
		}
	}

	@property OutputRange sink()
	{
		return OutputRange(cast(shared)this);
	}

	// Thread safe
	final shared(TimeoutEvent) scheduleTimeoutNow(Variant userData = Variant.init)
	{
		return scheduleTimeout(dur!"hnsecs"(0), userData);
	}
	
	// Thread safe
	final shared(TimeoutEvent) scheduleTimeout(Duration dt, Variant userData = Variant.init)
	{
		auto e = CoreEvents.create!TimeoutEvent(false);
		e.timestamp = MonoTime.currTime + dt;
		e.userData = userData;

		if (Thread.getThis().id == _ownerThreadID)
		{
			pendingTimeouts ~= cast(shared) e;
		}
		else
		{
			put(e);
		}
		return cast(shared) e;
	}

	// Thread safe
    final bool abortTimeout(shared(TimeoutEvent) scheduledTimeoutEvent) 
    {
		if (Thread.getThis().id == _ownerThreadID)
		{
			return abortTimeoutInOwnerThread(scheduledTimeoutEvent);
		}
		else
		{
			// Tell main thread to abort the timeout
			scheduledTimeoutEvent.aborted = true;
			_threadQueue.pushBusyWait(scheduledTimeoutEvent);
			signalEventQueuedByOtherThread();
			return true;
		}
    }

protected:
	// A timeout should always put a TimeoutEvent on the queue
	abstract Event poll(Duration timeout_);

	// Called by other threads that just called put(event) on 
	// us in order to wake us up and handle the event.
	abstract void signalEventQueuedByOtherThread();

	// non shared access to the owner queue because it is only owner thread that access it
	final @property Queue!Event ownerQueue()
	{
		return cast(Queue!Event) _ownerQueue;
	}

private:
	import deadcode.core.container;
	import deadcode.util.queue;


	// non shared access to the owner queue because it is only owner thread that access it
	@property ref shared(TimeoutEvent)[] pendingTimeouts()
	{
		return cast(shared(TimeoutEvent)[]) _pendingTimeouts;
	}

    final bool abortTimeoutInOwnerThread(shared(TimeoutEvent) scheduledTimeoutEvent)
	{
		for (size_t i = _pendingTimeouts.length; i > 0; --i)
		{
			size_t idx = i - 1;

			// Comparing addresses of TimeoutEvents since comparing shared ones doesn't work
			if (cast(TimeoutEvent)_pendingTimeouts[idx] == cast(TimeoutEvent)scheduledTimeoutEvent)
			{
				(cast(TimeoutEvent) scheduledTimeoutEvent).dispose();
					// Remove from list.
				if (_pendingTimeouts.length > 1)
					_pendingTimeouts[idx] = _pendingTimeouts[$-1];
				_pendingTimeouts.length -= 1;
				assumeSafeAppend(pendingTimeouts);
				return true;
			}
		}
		return false;
	}

	final Event _front()
	{
		while (!stopped)
		{
			if (!ownerQueue.empty)
				return ownerQueue.dequeue();

			while (!_threadQueue.empty)
			{
				auto e = _threadQueue.pop();
				if (e.type == CoreEvents.timeout)
				{
					//import std.stdio;
					//writeln(cast(Event)e, " ", e.type, " ", CoreEvents.timeout);
					//stdout.flush();
					auto toe = cast(shared(TimeoutEvent)) e; 
					assert(toe !is null);
					if (toe.aborted)
					{
						abortTimeoutInOwnerThread(toe);
					}
					else
					{
						// Just put this TimeoutEvent in the timeout array
						// Ok to cast shared away here because at this point this
						// thread owns this event.
						auto ts = (cast(Event)e).timestamp;
						if (ts <= MonoTime.currTime)
							return cast(Event) e;
				
						pendingTimeouts ~= cast(shared(TimeoutEvent))e;
					}
					//isRetry = false;
				}
				else
				{
					return cast(Event) e; // cast away shared and take ownership
				}
			}

			// Handle timeout event queue
			size_t idx;
			Event res = nextTimeoutEvent(idx);

			Duration nextTimeout = _timeout;
			if (res !is null)
			{
				auto dt = res.timestamp - MonoTime.currTime;
				if (dt <= dur!"hnsecs"(0))
				{
					// Got a timeout
					if (_pendingTimeouts.length > 1)
						_pendingTimeouts[idx] = _pendingTimeouts[$-1];
					_pendingTimeouts.length = _pendingTimeouts.length - 1;
					assumeSafeAppend(_pendingTimeouts);
					return res;
				}

				if (dt < nextTimeout)
					nextTimeout = dt;
			}

			if (stopped)
				return null;
		
			// In case of a retry there should always be an even in a queue since
			// the poll has returned. 
			//assert(!isRetry);
		
			res = poll(nextTimeout);
			if (res !is null)
			{
				res.timestamp = MonoTime.currTime;

				return res;
			}

			// second chance to handle events posted from other threads
			// or timeout events ready after the poll timeout
		}
		assert(0);
	}

	final Event nextTimeoutEvent(ref size_t idxOut)
	{
		idxOut = 0;
		Event res = null;
		foreach (i, e; _pendingTimeouts)
		{
			auto ev = cast(Event)e;
			if (res is null || res.timestamp > e.timestamp)
			{
				res = ev;
				idxOut = i;
			}
		}
		return res;
	}
}

version (unittest)
{
	import deadcode.test;
	import std.algorithm;
	import std.array;
	import std.concurrency;
	import std.range;
	import std.stdio;

	abstract class EvBase : Event
	{
		int source = 0;
	}

	class Ev1a : EvBase {  } // Directly put from owner thread
	class Ev1b : EvBase {  } // Put through poll by owner thread
	class Ev2 : EvBase {   }  // Put by other thread

	struct Fixture
	{
		class ES : MainEventSource
		{
			this() 
			{
				super(new SystemTimer());
                _globalTid = thisTid;
				_mainTid = spawn(&mainSource, thisTid);
				_otherTid = spawn(&otherSource, thisTid, cast(shared)this);
			}

			@property Tid mainTid() { return cast(Tid)_mainTid; }
			@property Tid globalTid() { return cast(Tid)_globalTid; }
			@property Tid otherTid() { return cast(Tid)_otherTid; }

			void fakeMainEvent(Event e)
			{
				mainTid.send(cast(immutable(EvBase))e);
			}

			void fakeOtherEvent(Event e)
			{
				otherTid.send(cast(immutable(EvBase))e);
			}

			override void stop()
			{
				super.stop();
				mainTid.send(true);
				otherTid.send(true);

				// Get all signals not collected
				while (receiveTimeout(Duration.zero,
							   (bool sig) {
							   }
							   )) {}
			}

			override Event poll(Duration timeout_)
			{
				import core.time;
				Event pollEvent = null;

				bool gotSome = 
					receiveTimeout(timeout_,
						(immutable(Event) ev) { 
							auto e = cast(EvBase)ev;
							pollEvent = e;
							e.source = 1;
						},
						(bool sig) {
						}
						);
				
				return pollEvent;
			}

			override void signalEventQueuedByOtherThread()
			{
				globalTid.send(true);
			}

			bool woken;
			Tid _globalTid;
			Tid _mainTid;
			Tid _otherTid;
		}

		static void mainSource(Tid mainThreadTid)
		{
			// fake something like SDL_Poll here
			bool run = true;
			while (run)
			{
				receive((immutable(Event) ev)
							  {
								  mainThreadTid.send(ev);
							  },
						(bool sig) {
							run  = false;
						});
			}
		}

		static void otherSource(Tid mainThreadTid, shared(ES) es)
		{
			ES es2 = cast(ES)es;
			// fake something like libasync here
			bool run = true;
			while (run)
			{
				receive((immutable(Event) e) {
						auto ev = cast(EvBase)e;
						ev.source = 2;
						es2.sink.put(ev);
					},
					(bool sig) {
						run  = false;
					});
			}
		}
	}

//EventManager mgr;
//shared static this()
//{
//    mgr = new EventManager();
//    mgr.activateRegistrantBySystemName("Core");
//}

}
version(none):
// Empty source works
unittest
{
	auto fes = new Fixture.ES();
	fes.stop();
	Assert(fes.empty);
}

// Timeout source works
unittest
{
	auto fes = new Fixture.ES();
	fes.timeout = 0.0;
	Assert(!fes.empty);
	auto e = fes.front;
	Assert(cast(TimeoutEvent)e !is null);
	fes.stop();
}

// Local put works
unittest
{
	auto fes = new Fixture.ES();
	auto e = new Ev1a;
	fes.put(e);
	Assert(!fes.empty);
	AssertRangesEqual(only(e), fes.take(1).array);
	fes.stop();
}

// Main thread put works with poll
unittest
{
	auto fes = new Fixture.ES();
	auto e = new Ev1b;
	Assert(!fes.empty);
	fes.fakeMainEvent(e);
	auto arr = fes.take(1).array;
	fes.stop();
	AssertRangesEqual(only(e), arr);
	Assert((cast(EvBase)arr[0]).source == 1);
}

// Main thread put works with poll multi
unittest
{
	auto fes = new Fixture.ES();
	auto e = new Ev1b;
	Assert(!fes.empty);
	fes.fakeMainEvent(e);
	fes.fakeMainEvent(e);
	fes.fakeMainEvent(e);
	auto arr = fes.take(3).array;
	fes.stop();
	AssertRangesEqual(only(e,e,e), arr);
	Assert((cast(EvBase)arr[0]).source == 1);
}

// Other thread put works with poll
unittest
{
	auto fes = new Fixture.ES();
	auto e = new Ev2;
	assert(!fes.empty);
	fes.fakeOtherEvent(e);
	auto arr = fes.take(1).array;
	fes.stop();
	AssertRangesEqual(only(e), arr);
	Assert((cast(EvBase)arr[0]).source == 2);
}

// Other thread put works with poll multi
unittest
{
	auto fes = new Fixture.ES();
	auto e = new Ev2;
	Assert(!fes.empty);
	fes.fakeOtherEvent(e);
	fes.fakeOtherEvent(e);
	fes.fakeOtherEvent(e);
	auto arr = fes.take(3).array;
	fes.stop();
	AssertRangesEqual(only(e,e,e), arr);
	Assert((cast(EvBase)arr[0]).source == 2);
}

// Mixed thread put works with poll multi
unittest
{
	import std.algorithm;
	auto fes = new Fixture.ES();
	auto e1a = new Ev1a;
	auto e1b = new Ev1b;
	auto e2 = new Ev2;
	Assert(!fes.empty);
	fes.fakeOtherEvent(e2);
	fes.fakeMainEvent(e1b);
	fes.fakeOtherEvent(e2);
	fes.put(e1a);
	fes.fakeMainEvent(e1b);
	fes.fakeOtherEvent(e2);
	auto arr = fes.take(6).array.sort!("a.toHash() < b.toHash()");
	fes.stop();

	// First all put events, then all main thread events, then other thread events
	AssertRangesEqual(only(e1a,e1b,e1b,e2,e2,e2).array.sort!("a.toHash() < b.toHash()") , arr);
}

// Timeout work
unittest
{
	auto fes = new Fixture.ES();
	auto e = new Ev2;
	Assert(!fes.empty);
	import core.time;

	auto timeoutEv = fes.scheduleTimeout(dur!"msecs"(100), Variant(42));
	auto arr = fes.take(1).array;
	fes.stop();
	Assert( (cast(TimeoutEvent)timeoutEv).userData.get!int, 42, "scheduleTimeout");
	//AssertRangesEqual(only(cast(TimeoutEvent)timeoutEv), arr);
}

unittest
{
	import std.algorithm;
	static bool cmp(EventDescription a, EventDescription b)
	{
		return a.system < b.system || ( a.system == b.system && a.name < b.name); 
	}

	auto expectedNames = ["Ev1a", "Ev1b", "Ev2", "QuitEvent", "TimeoutEvent"]; 

	AssertRangesEqual(expectedNames, 
				EventManager.eventDescriptions.dup.remove!(a => a.name == "Invalid").sort!cmp.array.map!(a=>a.name));

	Assert(CoreEvents.ev2, EventManager.lookup("Ev2")); 
}	
