module deadcode.core.container;

import deadcode.test;

class Stack(T)
{
	T[] _stack;

	void push(T v)
	{
		assumeSafeAppend(_stack);
		_stack ~= v;
	}

    @property size_t size() const pure nothrow @safe
    {
        return _stack.length;
    }

	@property bool empty() const pure nothrow @safe
	{
		return _stack.length == 0;
	}

	@property T top()
	{
		return _stack[$-1];
	}

	// Locate item in stack and remove it from stack
	bool remove(T item)
	{
		foreach (i, v; _stack)
		{
			if (v == item)
			{
				assumeSafeAppend(_stack);
				if (i != _stack.length - 1)
					moveAll(_stack[i+1..$], _stack[i..$-1]);
				_stack.length = _stack.length - 1;
                assumeSafeAppend(_stack);
				return true;
			}
		}
		return false;
	}

	// Locate item in stack and remove it from stack even if there multiple times
	bool removeAll(T item)
	{
		bool removedSome = false;
		while (remove(item)) { removedSome = true;}
		return removedSome;
	}

	T pop()
	{
		assumeSafeAppend(_stack);
		auto v = _stack[$-1];
		_stack.length = _stack.length - 1;
		return v;
	}
}

version (DeadcodeCoreTest)
unittest
{
	Stack!int s = new Stack!int;
	s.push(1);
	s.push(2);
	s.push(3);
	s.remove(2);
    auto l1 = s.size;
    s.remove(32);
    Assert(l1, s.size, "Removing non-existing element doens't change stack size");
	Assert(3, s.top);
    Assert(3, s.pop());
	Assert(1, s.pop());

    s.push(2);
	s.push(3);
    s.push(2);
    s.push(2);
	s.push(3);
    auto l2 = s.size;
    s.removeAll(2);
    Assert(l2 - 3, s.size, "Removing all 2's changes stack size as expected");
}

version (DeadcodeCoreTest)
unittest
{
	Stack!int s = new Stack!int;
	s.push(1);
	s.push(2);
	s.push(3);
	Assert(3, s.pop());
	Assert(2, s.pop());
	Assert(1, s.pop());
	Assert(s.empty);

	s.push(1);
	s.push(2);
	Stack!int s2 = s;

	Assert(2, s2.pop());
	s2.push(4);
	Assert(4, s.pop());
}



class Queue(T)
{
	// Implementation use this array as a circular buffer
	T[] _queue; // Ths queu 
	size_t _begin;
	size_t _end;

	this(size_t reserveSize = 8)
	{
		if (reserveSize == 0)
			reserveSize = 2; // do not allow 0 size queue

		// capacity might be more that we try to reserve
		_queue.length = _queue.reserve(reserveSize);
	}

	void enqueueIfRoom(T v) @nogc
	{
		auto newEnd = _end+1;
		if (newEnd == _begin || (newEnd == _queue.length && _begin == 0))
			return; // no room... would allocate

		assert(_end < _queue.length);
		_queue[_end++] = v;

		if (_end == _queue.length)
		{
			// Wrap around because there is room at the start of the array
			_end = 0;
		}
	}

	void enqueue(T v)
	{
		assert(_end < _queue.length);
		_queue[_end++] = v;
		
		if (_end == _queue.length)
		{
			// is the queue full?
			if (_begin == 0)
			{
				// extend the queue. Since we know that 
				// capacity is reached we can simply 
				_queue.length++;
				_queue.length = _queue.capacity;
			}
			else
			{
				// Wrap around because there is room at the start of the array
				_end = 0;
			}
		}
		else if (_end == _begin)
		{
			// out of room
			T[] newQueue;
			// capacity might be more that we try to reserve
			newQueue.length = newQueue.reserve(_queue.length * 2);
			auto endSize = _queue.length - _begin;
			newQueue[0.._end] = _queue[0.._end];
			newQueue[$-endSize..$] = _queue[$-endSize..$];
			_begin = newQueue.length - endSize;
			_queue = newQueue;
			assert(_begin >= 0);
		}
	}

	@property bool empty() const pure nothrow @safe
	{
		return _begin == _end;
	}

	@property T front()
	{
		return _queue[_begin];
	}

	void popFront()
	{
		dequeue();
	}

	// Locate item in queue and remove it from queue
	//bool remove(T item)
	//{
	//    // 
	//    foreach (i, v; _queue)
	//    {
	//        if (v == item)
	//        {
	//            assumeSafeAppend(_queue);
	//            if (i != _queue.length - 1)
	//                _queue[i..$-1] = _queue[i+1..$];
	//            _queue.length = _queue.length - 1;
	//            return true;
	//        }
	//    }
	//    return false;
	//}


	// Locate item in stack and remove it from queue even if there multiple times
	//bool removeAll(T item)
	//{
	//    bool removedSome = false;
	//    while (remove(item)) { removedSome = true;}
	//    return removedSome;
	//}

	T dequeue()
	{
		assert(_begin != _end);
		T v = _queue[_begin++]; 
		_queue[_begin-1] = T.init;
		if (_begin == _queue.length)
		{
			// We need to wrap the _begin marker to the end of the _queue
			_begin = 0;
		}
		return v;
	}
}

version (DeadcodeCoreTest)
version (unittest)
{
	import std.stdio;
	import std.algorithm;
	void chk(T)(T q, size_t b, size_t e, string file = __FILE__, int line = __LINE__, string func = __FUNCTION__)
	{
		version (verboseunittest)
			writeln(q._queue.capacity, " ", q._queue.length, " ", q._begin, " ", q._end);
		Assert(q._begin, b, "", file, line, func);
		Assert(q._end, e, "", file, line, func);		
	}

	void chk(T)(T q, size_t cap, size_t len, size_t b, size_t e, string file = __FILE__, int line = __LINE__, string func = __FUNCTION__)
	{
		version (verboseunittest)
			writeln(q._queue.capacity, " ", q._queue.length, " ", q._begin, " ", q._end);
		Assert(q._queue.capacity, cap, "", file, line, func);
		Assert(q._queue.length, len, "", file, line, func);
		Assert(q._begin, b, "", file, line, func);
		Assert(q._end, e, "", file, line, func);		
	}
}

struct T { string n; }

version (DeadcodeCoreTest)
unittest
{
	Queue!int s = new Queue!int(0);
    auto cap = s._queue.capacity; 
    Assert(cap != 0, "Queue capacity is never zero");
    
    foreach (i; 0 .. cap+1)
        s.enqueueIfRoom(1);
    
    Assert(cap, s._queue.capacity, "Queue.enqueueIfRoom will not change capacity");
    s.dequeue();
    s.enqueueIfRoom(1);
    Assert(cap, s._queue.capacity, "Queue.enqueueIfRoom after queue buffer wrap will not change capacity");
}

version (DeadcodeCoreTest)
@T("queue and dequeue until empty")
unittest
{
	//      b
	//      e  
	// | | | |
	Queue!int s = new Queue!int(2);
	s.enqueue(1);
	s.enqueue(2);
	Assert(1, s.dequeue());
	Assert(2, s.dequeue());
	s.chk(2,2);
	Assert(equal(s, [1][0..0]));
}

version (DeadcodeCoreTest)
@T("will resize when exceeding buffer length")
unittest
{
	//  b    
	//       e 
	// |1|2|3| | | | | 
	Queue!int s = new Queue!int(2);
	s.chk(3,3,0,0);
	s.enqueue(1);
	s.enqueue(2);
	s.enqueue(3);
	s.chk(7,7,0,3);
	Assert(equal(s, [1,2,3]));
}

version (DeadcodeCoreTest)
@T("head will wrap")
unittest
{
	//    b  
	// e      
	// | |2|3|
	Queue!int s = new Queue!int(2);
	s.enqueue(1);
	s.enqueue(2);
	Assert(1, s.dequeue());
	s.enqueue(3);
	s.chk(1,0);
	Assert(equal(s, [2,3]));
}

version (DeadcodeCoreTest)
@T("will resize when exceeding buffer size in the middle")
unittest
{
	//            b
	//   e
	// |4| | | | |2|3| 
	Queue!int s = new Queue!int(2);
	s.enqueue(1);
	s.enqueue(2);
	Assert(1, s.dequeue());
	s.enqueue(3);
	s.enqueue(4);
	s.chk(7,7,5,1);
	Assert(equal(s, [2,3,4]));
}

version (DeadcodeCoreTest)
@T("tail will wrap")
unittest
{
	//  b   
	//   e  
	// |4| | |
	Queue!int s = new Queue!int(2);
	s.enqueue(1);
	s.enqueue(2);
    Assert(1, s.dequeue());
	Assert(2, s.dequeue());
	s.enqueue(3);
	s.enqueue(4);
	Assert(3, s.dequeue());
	s.chk(3,3,0,1);
	Assert(equal(s, [4]));
}
