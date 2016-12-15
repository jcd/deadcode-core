module deadcode.core.weakref;

// ////////////////////////////////////////////////////////////////////////// //
// a thread-safe weak reference implementation
// based on the code from http://forum.dlang.org/thread/jjote0$1cql$1@digitalmars.com
import core.atomic, core.memory;

private alias void delegate (Object) DEvent;
private extern (C) void rt_attachDisposeEvent (Object h, DEvent e);
private extern (C) void rt_detachDisposeEvent (Object h, DEvent e);

final class Weak(T : Object) {
	// Note: This class uses a clever trick which works fine for
	// a conservative GC that was never intended to do
	// compaction/copying in the first place. However, if compaction is
	// ever added to D's GC, this class will break horribly. If D ever
	// gets such a GC, we should push strongly for built-in weak
	// references.

	private size_t mObject;
	private size_t mPtr;
	private size_t mHash;

	this (T obj=null) @trusted {
		hook(obj);
	}

	@property T object () const @trusted nothrow {
		auto obj = cast(T)cast(void*)(atomicLoad(*cast(shared)&mObject)^0xa5a5a5a5u);
		// we've moved obj into the GC-scanned stack space, so it's now
		// safe to ask the GC whether the object is still alive.
		// note that even if the cast and assignment of the obj local
		// doesn't put the object on the stack, this call will.
		// so, either way, this is safe.
		if (obj !is null && GC.addrOf(cast(void*)obj)) return obj;
		return null;
	}

	@property void object (T obj) @trusted {
		auto oobj = cast(T)cast(void*)(atomicLoad(*cast(shared)&mObject)^0xa5a5a5a5u);
		if (oobj !is null && GC.addrOf(cast(void*)oobj)) unhook(oobj);
		oobj = null;
		hook(obj);
	}

	@property bool empty () const @trusted nothrow {
		return (object is null);
	}

	void clear () @trusted { object = null; }

	void opAssign (T obj) @trusted { object = obj; }

	private void hook (Object obj) @trusted {
		if (obj !is null) {
			//auto ptr = cast(size_t)cast(void*)obj;
			// fix from Andrej Mitrovic
			auto ptr = cast(size_t)*(cast(void**)&obj);
			// we use atomics because not all architectures may guarantee atomic store and load of these values
			atomicStore(*cast(shared)&mObject, ptr^0xa5a5a5a5u);
			// only assigned once, so no atomics
			mPtr = ptr^0xa5a5a5a5u;
			mHash = typeid(T).getHash(&obj);
			rt_attachDisposeEvent(obj, &unhook);
			GC.setAttr(cast(void*)this, GC.BlkAttr.NO_SCAN);
		} else {
			atomicStore(*cast(shared)&mObject, cast(size_t)0^0xa5a5a5a5u);
		}
	}

	private void unhook (Object obj) @trusted {
		rt_detachDisposeEvent(obj, &unhook);
		// this assignment is important.
		// if we don't null mObject when it is collected, the check
		// in object could return false positives where the GC has
		// reused the memory for a new object.
		atomicStore(*cast(shared)&mObject, cast(size_t)0^0xa5a5a5a5u);
	}

	override bool opEquals (Object o) @trusted nothrow {
		if (this is o) return true;
		if (auto weak = cast(Weak!T)o) return (mPtr == weak.mPtr);
		return false;
	}

	override int opCmp (Object o) @trusted nothrow {
		if (auto weak = cast(Weak!T)o) return (mPtr > weak.mPtr ? 1 : mPtr < weak.mPtr ? -1 : 0);
		return 1;
	}

	override size_t toHash () @trusted nothrow {
		auto obj = object;
		return (obj ? typeid(T).getHash(&obj) : mHash);
	}

	override string toString () @trusted {
		auto obj = object;
		return (obj ? obj.toString() : toString());
	}
}