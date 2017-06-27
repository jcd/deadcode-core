module deadcode.core.coreevents;

import std.variant;

import deadcode.core.event;

class TimeoutEvent : Event
{
	private this() {}
    this(bool _aborted, Variant data = Variant.init)
	{
		aborted = _aborted;
		userData = data;
	}
	bool aborted = false;
	Variant userData;
}

class QuitEvent : Event
{
}

// Core events are in this module itself ie. TimeoutEvent and QuitEvent
mixin registerEvents!"Core";
