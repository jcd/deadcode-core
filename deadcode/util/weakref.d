/**
* This module implements weak references.
*
* Grabbed from https://github.com/w0rp/dstruct/blob/master/source/dstruct/weak_reference.d
*
*
*
* Authors: Alex Rønne Petersen, w0rp
*
* Credit and thanks goes to Alex Rønne Petersen for implementing
* another weak reference type. This type is pretty much a fork of his
* code, some of it still surviving.
*

Copyright (c) 2015, w0rp <devw0rp@gmail.com>
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

*
*/
module deadcode.util.weakref;

import core.memory;
import core.atomic;

private alias void delegate(Object) DEvent;
private extern (C) void rt_attachDisposeEvent(Object h, DEvent e);
private extern (C) void rt_detachDisposeEvent(Object h, DEvent e);

private alias extern(C) void
function(Object, DEvent) @system pure nothrow
PureEventFunc;

/**
* This class implements a weak reference wrapper for class T.
*
* A weak reference will not prevent the object from being collected
* in a garbage collection cycle. If and when the object is collected,
* the internal reference to object will become null.
*
* This weak reference wrapper is thread safe.
*
* Params:
*     T = The type of class.
*/
final class WeakRef(T) if(is(T == class) || is(T == interface)) {
private:
    shared size_t _ptr;
    
    @trusted pure nothrow
        private void freeWrapper(Object obj) {
            if (_ptr == 0) {
                // We already cleaned up, don't do it again.
                return;
            }

            // Set the invalid pointer to null so we know it's gone.
            atomicStore(_ptr, cast(size_t) 0);
        }

    private void disposed(Object obj) {
        freeWrapper(obj);
    }
public:
    /**
    * Create a weak reference wrapper for a given object.
    *
    * Params:
    *     object = The object to hold a reference to.
    */
    @trusted pure nothrow
        this(T object) {
            if (object is null) {
                // No work needs to be done for null.
                return;
            }

            // Set the pointer atomically in a size_t so it's not a valid pointer.
            // Use cast(void**) to avoid opCast problems.
            atomicStore(_ptr, cast(size_t) cast(void**) object);

            // Stop the GC from scanning inside this class.
            // This will make the interior reference a weak reference.
            uint astart = GC.getAttr(cast(void*) this);
            uint aend = GC.setAttr(cast(void*) this, GC.BlkAttr.NO_SCAN);

            // Call a special D runtime function for nulling our reference
            // to the object when the object is destroyed.
            (cast(PureEventFunc) &rt_attachDisposeEvent)(
                                                         cast(Object) object,
                                                         &disposed
                                                             );
        }

    @trusted pure nothrow
        ~this() {
            // freeWrapper();
                        // Detach the previously attached dispose event, it is done.
            //(cast(PureEventFunc) &rt_detachDisposeEvent)(
            //                                             //cast(Object) cast(void*) _ptr,
            //                                             cast(Object) _obj,
            //                                             &disposed
            //                                                 );
            //uint astart = GC.getAttr(cast(void*) this);
            //uint aend = GC.setAttr(cast(void*) this, GC.BlkAttr.NONE);
        }

    /**
    * Return the referenced object held in this weak reference wrapper.
    * If and when the object is collected, this function will return null.
    *
    * Returns: The referenced object.
    */
    @trusted pure nothrow
        T get() inout {
            auto ptr = cast(void*) atomicLoad(_ptr);

            // Check if the object is still alive before we return it.
            // It might be killed in another thread.
            return GC.addrOf(ptr) ? cast(T) ptr : null;
        }

    //@trusted pure nothrow opCast(U)() inout if (is(U == T)) {
    //    return get(); 
    //}

    /**
    * Params:
    *     other = Another object.
    *
    * Returns: True the other object is a weak reference to the same object.
    */
    @safe pure nothrow
        override bool opEquals(Object other) const {
            if (other is this) {
                return true;
            }

            if (auto otherWeak = cast(WeakRef!T) other) {
                return _ptr == otherWeak._ptr;
            }

            return false;
        }

    /// ditto
/*
    @trusted pure nothrow
        final override bool opEquals(const(Object) other) const {
            return this.opEquals(cast(Object) other);
        }
        */
}

/**
* This is a convenience function for creating a new
* weak reference wrapper for a given object.
*
* Params:
*     object = The object to create a reference for.
*
* Returns: A new weak reference to the given object.
*/
WeakRef!T weak(T)(T object) if(is(T == class) || is(T == interface)) {
    return new WeakRef!T(object);
}

// Test that the reference is held.
unittest {
    class SomeType { }

    SomeType x = new SomeType();
    auto y = weak(x);

    assert(y.get() is x);
}

// Test that the reference is removed when the object is destroyed.
unittest {
    class SomeType { }

    SomeType x = new SomeType();
    auto y = weak(x);

    destroy(x);

    assert(y.get() is null);
}

// Test equality based on the reference held in the wrappers.
unittest {
    class SomeType { }

    SomeType x = new SomeType();
    auto y = weak(x);
    auto z = weak(x);

    assert(y !is z);
    assert(y == z);
}

// Test equality after nulling things.
unittest {
    class SomeType { }

    SomeType x = new SomeType();
    auto y = weak(x);
    auto z = weak(x);

    destroy(x);

    assert(y !is z);
    assert(y == z);
}

// Test tail-const weak references.
unittest {
    class SomeType { }

    const x = new SomeType();
    const y = new SomeType();

    auto z = weak(x);
    z = weak(y);
}