module deadcode.core.event;

import core.time : MonoTime, Duration, dur;
import std.typecons : Tuple, AliasSeq;
import std.variant;

import deadcode.util.string : munch;

alias EventType = ushort;

enum EventUsed
{
	no = 0,
	yes = 1
}

class Event
{
	enum invalidType = 0;
	EventType type = invalidType;
	MonoTime timestamp;
    bool used = false;
	void function(Event) disposeFunc;
	debug string debugName; 

	final void dispose()
	{
		disposeFunc(this);
	}

	final void markUsed()
	{
		used = true;
	}

	final @property bool isValid() const pure @safe @nogc nothrow 
	{
		return type != invalidType;
	}

	@property bool allowCombine() pure @safe nothrow const
	{
		return false;
	}

	// Returns true if events could be combined and in that case
	// just use this event and dispose the argument event.
	bool combineIntoThis(Event e)
	{
		assert(0); // only allowed allowCombine has returned true and subclass has overridden this method
	}
}

struct EventDescription
{
	string system;
	string name;
    Event delegate() factory;
    const(EventType*) eventType;
}

alias I(alias T) = T;
//alias I(T...) = T;

//interface IEventRegistrant 
//{
//    @property string name() const pure nothrow @safe @nogc;
//    void register(EventManager mgr);
//}

template filterEventType(alias Mod)  
{
	template filterEventType(string member)  
	{
		import std.traits;
		static if (is ( I!(__traits(getMember, Mod, member)) ) )
		{
			alias mem = I!(__traits(getMember, Mod, member));
			static if (is(mem : Event) && !isAbstractClass!mem && ! is(mem == Event))
			{
				//static if (staticIndexOf!(Event, BaseClassesTuple!mem) != -1 && !isAbstractClass!mem)
				//static if (!isAbstractClass!mem)
				//{
					//pragma(msg, "Register2 event " ~ member);
					alias filterEventType = Tuple!(mem, member); // toLower(member[0..1]) ~ member[1..$];
					// return mem;
					//mem.staticType = mgr.register(EventDescription(system, eventName));
				//}
				//else
				//{
//					alias filterEventType = AliasSeq!();
	//			}
			}
			else
			{
				alias filterEventType = AliasSeq!();
			}
		}
		else
		{
			alias filterEventType = AliasSeq!();
		}
	}
}

// e.g. 
// MyClass -> myClass 
// DNAClass -> dnaClass
// dnaClass -> dnaClass
string identifierToFieldName(string cname)
{
	import std.string;
	import std.algorithm;
	auto i = munch(cname, "A-Z");
	if (cname.length == 0)
		return toLower(i); // all uppercase
	else if (i.length == 0)
		return cname;      // all lowercase 
	else if (i.length == 1)
		return toLower(i) ~ cname; // the MyClass case
	else
		return toLower(i[0..$-1]) ~ i[$-1] ~ cname; // the MYClass case
}

unittest
{
	import deadcode.test;
	Assert("", identifierToFieldName(""));
	Assert("a", identifierToFieldName("A"));
	Assert("a", identifierToFieldName("a"));
	Assert("myClass", identifierToFieldName("MyClass"));
	Assert("dnaClass", identifierToFieldName("DNAClass"));
	Assert("dnaClass", identifierToFieldName("dnaClass"));
	Assert("dna", identifierToFieldName("DNA"));
	enum foo = identifierToFieldName("MyClass");
	Assert("myClass", foo, "CTFE");
}

string identifierToEventFieldName(string cname)
{
	auto n = identifierToFieldName(cname);
	
	// strip "Event" suffix
	enum suffix = "Event";
	enum l = suffix.length;
	
	if (n.length > 5 && n[$-l..$] == suffix)
		return n[0..$-l];
	return n;
}

unittest
{
	import deadcode.test;
	Assert("", identifierToEventFieldName(""));
	Assert("event", identifierToEventFieldName("Event"));
	Assert("foo", identifierToEventFieldName("FooEvent"));
}

mixin template registerEvents(string system, string modStr = __MODULE__)
{
	import std.traits;
	// pragma (msg, "registerEvents " ~ modStr);
	alias mod = I!(mixin(modStr));
	import std.meta;
	import std.string;
	import std.traits;

	alias EventTypes = staticMap!(filterEventType!mod, __traits(allMembers, mod));

	private string getEventTypesStructMembers(T...)()
	{
		size_t minSize = 0;
		size_t maxSize = 0;
		string eventTypesString = "";
		foreach (t; T)
		{
			auto sz =  __traits(classInstanceSize, t.Types[0]);
			minSize = sz < minSize ? sz : minSize;
			maxSize = sz > maxSize ? sz : maxSize;
			eventTypesString ~= t.fieldNames[0] ~ ", ";
		}

		import std.conv;
		string minSizeStr = minSize.to!string;
		string maxSizeStr = maxSize.to!string;

		string res = "struct " ~ system ~ "Events {";
		res ~= q{  
  import std.experimental.allocator.building_blocks.free_list;
  import std.experimental.allocator.gc_allocator;
  import std.conv;
  static FreeList!(GCAllocator, %s, %s) _allocator;
  alias EventTypes = AliasSeq!(%s);
  
  static void dispose(Event e) 
  { 
      auto support = (cast(void*)e)[0 .. typeid(e).initializer().length];
      destroy(e);
      _allocator.deallocate(support);
  }
  
  static Event deserialize(alias deserializer, Args...)(string name, Args args)
  {
      foreach (cls; EventTypes)
      {
          if ( cls.stringof == name )
          {
              cls ev = create!cls();
              return deserializer!cls(ev, args);
          }
      }
      return null;
  }

  static T create(T, Args...)(Args args) 
  {
      void[] data = _allocator.allocate(typeid(T).initializer().length);
      auto e = emplace!(T)(data, args);
      debug e.debugName = T.stringof;
      e.type = mixin(identifierToEventFieldName(T.stringof));
      e.disposeFunc = &dispose;
      return e;
  
  }}.format(minSizeStr, maxSizeStr, eventTypesString);
        string dispatchCode;
		foreach (t; T)
		{
			alias cls = t.Types[0];
			enum n = t.fieldNames[0];
			enum eventName = identifierToEventFieldName(n);
			res ~= "  static __gshared EventType " ~ eventName ~ ";\n";
			dispatchCode ~= "    } else if (t == " ~ eventName ~ ") {\n"
				~ "      static if (is(typeof(target.on" ~ n ~ ")))\n"
				~ "        return target.on" ~ n ~ "(cast(" ~ n ~ ")ev);\n"
				~ "      else\n"
				~ "        return EventUsed.no;\n";
		}
		res ~= "  static EventUsed dispatch(T)(T target, Event ev) {\n    auto t = ev.type;\n    if (false) {\n" ~ dispatchCode ~ "    } else return EventUsed.no;\n }\n";
		return res ~ "}\n";
	}

	// Generate fast lookup of event types for the system using e.g.
	// GUIEvents.onMouseOver
	// where system is GUI in this case.
	// pragma (msg, getEventTypesStructMembers!EventTypes);
	
    //pragma(msg, getEventTypesStructMembers!EventTypes);

	mixin(getEventTypesStructMembers!EventTypes);

    //class EventRegistrant : IEventRegistrant
    //{
    //    private bool _isRegistered = false;
    //
    //    override @property string name() const pure nothrow @safe @nogc
    //    {
    //        return system; // mod.stringof;
    //    }
    //
    //    override void register(EventManager mgr)
    //    {
    //        assert(!_isRegistered);
    //        _isRegistered = true;
    //
    //        import std.conv;
    //        foreach (clsDesc; EventTypes)
    //        {
    //            alias cls = clsDesc.Types[0];
    //            enum n = clsDesc.fieldNames[0];
    //            enum eventName = identifierToEventFieldName(n); // toLower(n[0..1]) ~ n[1..$];
    //            //pragma(msg, "Register event " ~ system ~ ":" ~ eventName);
    //            auto factory = delegate() { return mixin(system ~ "Events").create!cls(); };
    //            EventType et = mgr.register(EventDescription(system, n, factory, mixin("&" ~ system ~ "Events." ~ eventName)));
    //            // cls.staticType = et;
    //            mixin(system ~ "Events." ~ eventName ~ " = et;");
    //        }
    //    }
    //}

	shared static this ()
	{
        import std.conv;
        foreach (clsDesc; EventTypes)
        {
            alias cls = clsDesc.Types[0];
            enum n = clsDesc.fieldNames[0];
            enum eventName = identifierToEventFieldName(n); // toLower(n[0..1]) ~ n[1..$];
            //pragma(msg, "Register event " ~ system ~ ":" ~ eventName);
            auto factory = delegate() { return mixin(system ~ "Events").create!cls(); };
            EventType et = EventManager.register(EventDescription(system, n, factory, mixin("&" ~ system ~ "Events." ~ eventName)));
            // cls.staticType = et;
            mixin(system ~ "Events." ~ eventName ~ " = et;");
        }
		// EventManager.addRegistrant(new EventRegistrant());
	}
}

/*
struct Type
{
	size_t id;
	ushort index;
}

struct TypeManager
{
	ushort[size_t] idToIndex;
	Type[] types;

	void InitType(TypeInfo_Class c)
	{
		auto entry = c.toHash() in idToIndex;
		if (entry is null)
		{
			types ~= Type(c.toHash(), types.length);
			idToIndex[c.toHash()] = types.length - 1;
		}
	}
}

ushort TypeIndex(T)()
{
	auto idx = TypeManager.idToIndex[typeid(T).toHash()];
	return idx;
}

shared static this ()
{
	import std.stdio;
	writeln("All classes");
	foreach (m; ModuleInfo)
	{
		auto clss = m.localClasses;
		foreach (cls; clss)
		{
			writeln("  " ~ cls.name ~ " ", cls.toHash());
		}
	}
}
*/

class EventManager
{
	static @property const(EventDescription)[] eventDescriptions()
	{
		return _eventDescriptions;
	}
	
	shared static this()
	{
		auto ed = register(EventDescription("Builtin", "Invalid"));
		assert(ed == Event.invalidType);
	}

    //static void addRegistrant(IEventRegistrant r)
    //{
    //    assert(!_eventRegistrationFinished);
    //    _eventRegistrants ~= r;
    //}

    //void activateRegistrants()
    //{
    //    foreach (r; _eventRegistrants)
    //    {
    //        r.register(this);
    //    }
    //}
    //
    //void activateRegistrantBySystemName(string systemName)
    //{
    //    foreach (r; _eventRegistrants)
    //    {
    //        if (r.name == systemName)
    //        {
    //            r.register(this);
    //            break;
    //        }
    //    }
    //}

	static EventType register(EventDescription d)
	{
		import std.exception;
		import std.stdio;
		// writeln("Event register " ~ d.system ~ "." ~ d.name);
		enforce(_eventDescriptions.length < EventType.max);
		_eventDescriptions ~= d;
		return cast(EventType) (_eventDescriptions.length - 1);
	}

	static EventType lookup(string name)
	{
		foreach (i, d; _eventDescriptions)
			if (d.name == name)
				return cast(EventType)i;
		return Event.invalidType;
	}

	private static EventDescription[] _eventDescriptions;	
    // private static IEventRegistrant[] _eventRegistrants;
}

