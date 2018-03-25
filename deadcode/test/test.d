module deadcode.test.test;

import std.stdio;
import std.string;
import std.conv;

// UDA to name unittest blocks
struct Test
{
    string contextDescription;
    string actionDescription;
    string expectedOutcomeDescription;
}

struct UnitTestInfo
{
	string fullName; // including nested classes etc.
	string aggregateName; // class/module/struct name
	int testNumber; // global
	int testScopeStartsAtLine;
}

static
{
	int g_Total = 0;
	struct TestRecord
	{
		bool success;
		string assertion;
		string msg;
		string file;
		int line;
		UnitTestInfo testInfo;
	}
	alias TestRecord[] TestRecords;
	TestRecords g_TestRecords;
	alias void function() UnitTestFunc;
	UnitTestFunc[string] g_ModuleUnitTests;
	UnitTestInfo[] g_TestOrder;
    bool g_RecordingOn = true;
}

UnitTestInfo parseUnitTestName(string func)
{
	// Parse func line e.g.
	string agName = "";
	int agAtLine = 0;
	int testNumber = 0;
	if (false)
	{
		// Old style:
		// math.region.Region.__unittestL60_63
		string[] f;
		if (func[0..2] != "__")
			agName = func[0..func.indexOf(".__")];
		const int DELIMLEN = 11; // __unittestL
		int offsBegin = cast(int)agName.length + DELIMLEN + (agName.length ? 1 : 0);
		int offsEnd = cast(int)func.indexOf("_", offsBegin);
		agAtLine = func[offsBegin..offsEnd].to!int;

		// In case of Asserts in member functions of classes defined in a unittest scope
		// we need to check of . after the __unittestLxx_xx
		int offsStop = cast(int)func.indexOf(".", offsEnd);

		testNumber = func[offsEnd+1.. offsStop == -1 ? func.length : offsStop].to!int;		
	}
	else
	{
		// New style
		// __unittest_mat_region_Region_d_60_63
		import std.stdio;
		//writeln(func);
		const int DELIMLEN = 11; // __unittest_
		auto idx = func.indexOf("_d_");
		if (idx != -1)
			agName = func[11..idx].replace("_",".");
	}
	return UnitTestInfo(func, agName, testNumber, agAtLine);
}

void recordTestResult(bool success, string assertion, string msg, string file, int line, string func)
{
	import std.stdio;
	auto info = parseUnitTestName(func);
	if (g_RecordingOn)
    {
    	g_Total++;
        g_TestRecords ~= TestRecord( success, assertion, msg, file, line, info);
	}
    version (TestingByDeadcode)
    {
		static import core.exception;
        import std.range;
		if (!success)
	        core.exception.onAssertErrorMsg(file, line, (assertion.empty ? "" : assertion ~ ": ") ~ msg);
    }
}

version (TestingByTool)
{
	import std.datetime;
	StopWatch sw;
    
    shared static this()
	{
		sw.start();
	}
	shared static ~this()
	{
		import std.stdio;
        printAllStats(stdout, sw);
	}

    void printAllStats(T)(T sink, ref StopWatch w)
    {
		sw.stop();
		printStats(sink,  true);
		sink.writeln("Time: " ~ sw.peek().to!("seconds", real).to!string ~ " seconds.");        
    }
}


TestRecord getTestResult(string filename, int unittestStartLine)
{
	TestRecords recs = g_TestRecords;
	foreach (rec; recs)
	{
		if (rec.testInfo.testScopeStartsAtLine == unittestStartLine && rec.file == filename)
			return rec;
	}
	return TestRecord();
}

unittest
{
	if (g_TestRecords.length != 0)
	{
	    auto r = g_TestRecords[0];
	    Assert(TestRecord(), getTestResult("<non-existing-file>", -1));
	    Assert(r, getTestResult(r.file, r.testInfo.testScopeStartsAtLine));		
	}
}

bool printStats(F)(F output, bool includeSuccessful = false)
{
	import std.algorithm;
    bool hasFailing = false;
	foreach (rec; g_TestRecords)
	{
		if (includeSuccessful || !rec.success)
			output.writeln(text("Test ", rec.file[0..$], ":", rec.line, " ", rec.msg, " ", rec.assertion, " ", rec.success ? "OK" : "FAILED"));
	    hasFailing = hasFailing || !rec.success;
    }

    if (includeSuccessful && hasFailing)
    {
	    output.writeln("\n************* Failing unittest subset extract from above listing:");
        foreach (rec; g_TestRecords)
	    {
		    if (!rec.success)
			    output.writeln(text("Test ", rec.file[0..$], ":", rec.line, " ", rec.msg, " ", rec.assertion, " ", rec.success ? "OK" : "FAILED"));
	    }
    }

	version (unittest)
	{
	}
	else
	{
		output.writefln("Warning: application not compiled with unittests enabled");
    }
	auto c = g_TestRecords.count!"a.success";
	output.writefln("Test results: %s of %s OK", c, g_Total);
    return c == g_Total;
}

unittest
{
    struct MockSink
    {
        void writeln(string) {}
        void writefln(A...)(A) {}
    }
    printStats(MockSink(), false);
    {
        import std.array;
        Assert(1,0); // register failed test
        printStats(MockSink(), true);
        g_TestRecords = g_TestRecords[0..$-1]; // remove failed test
        g_Total--;
        assumeSafeAppend(g_TestRecords);
    }

    version (TestingByTool)
    {
        StopWatch dummyStopWatch;
        printAllStats(MockSink(), dummyStopWatch);
    }
}

void Assert(lazy bool expMustBeTrue, string msg = "", string file = __FILE__, int line = __LINE__, string func = __FUNCTION__)
{
	bool res = false;
	try
	{
		res = expMustBeTrue();
		// writeln("Test ", file, "@", line, " ", msg, ": ", res ? "OK" : "FAILED");
	}
	catch (Exception e)
	{
		msg ~= text(" (Caught exception ", e, ")");
	}
	recordTestResult(res, "", msg, file, line, func);
}


// Mixing in this will scan the module and its aggregates for unittests and register them
// making it possible to run them at will later.
mixin template registerUnittests()
{
    version(unittest)
    {
	    shared static this()
	    {
		    import std.typetuple;
		    int a;

            alias tests = TypeTuple!(__traits(getUnitTests, __traits(parent,__traits(parent, a))));

            import std.string;
		    import std.algorithm;
            import std.traits;
            import std.typetuple;

            import std.stdio;
            //enum ii = __traits(identifier, __traits(parent,__traits(parent, a)));
            // pragma(msg, "Capturing tests in ii);
            // writeln("Capturing tests in " ~ ii);

		    // Module level tests
            foreach (tst; tests)
		    {
			    // ie. __unittestL235_52
			    //enum name = __traits(identifier, test)[11..$];
			    //enum name = __traits(identifier, test)[11..$];
			    //enum linen = name[0.. indexOf(name, "_")];
			    //import std.stdio;
                //writeln("Module Unittest: " ~ __traits(identifier, tst));

			    //if (textAnchor.number+1 == linen.to!uint)
			    //{
			    //    //writeln("FOOO " ~ line);
			    //    //	test();
			    //}
			    enum name = __traits(identifier, tst);
			    g_ModuleUnitTests[name] = &tst;
			    auto info = parseUnitTestName(name);
			    g_TestOrder ~= info;
		    }

            enum allmems = TypeTuple!(__traits(allMembers, __traits(parent,__traits(parent, a))));
            //enum aggregates = Filter!(isAggregateType, allmems);

            //   writeln("All members ", allmems);
            // Aggregate level tests
            foreach (agg; allmems)
            {
                static if (is(TypeTuple!(__traits(getMember, __traits(parent,__traits(parent, a)), agg))[0] == class) ||
                           is(TypeTuple!(__traits(getMember, __traits(parent,__traits(parent, a)), agg))[0] == struct))
                {
                    //alias mem = __traits(getMember, __traits(parent,__traits(parent, a)), agg);
                    alias aggTests = TypeTuple!(__traits(getUnitTests, __traits(getMember, __traits(parent,__traits(parent, a)), agg)));
                    foreach (tst; aggTests)
		            {
			            // ie. __unittestL235_52
			            //enum name = __traits(identifier, test)[11..$];
			            //enum name = __traits(identifier, test)[11..$];
			            //enum linen = name[0.. indexOf(name, "_")];
			            //import std.stdio;
                        // writeln("Aggregate Unittest: ", __traits(identifier, __traits(parent,__traits(parent, a))), " ", __traits(identifier, tst));

			            //if (textAnchor.number+1 == linen.to!uint)
			            //{
			            //    //writeln("FOOO " ~ line);
			            //    //	test();
			            //}
			            enum name = __traits(identifier, tst);
			            g_ModuleUnitTests[name] = &tst;
			            auto info = parseUnitTestName(name);
			            g_TestOrder ~= info;
		            }
                }
            }
		    sort!"a.testNumber < b.testNumber"(g_TestOrder);

	    };
    }
}

//void Assert(alias MOD, T, V)(lazy T thisExp, lazy V isEqualToThisExp, string msg = "", string file = __FILE__, int line = __LINE__, string func = __FUNCTION__)
//{
//
//
//}

void Assert(T, V)(lazy T thisExp, lazy V isEqualToThisExp, string msg = "", string file = __FILE__, int line = __LINE__, string func = __FUNCTION__)
{
	bool res = false;
	string explanation = "a == b";
	try
	{
		auto a = thisExp();
		auto b = isEqualToThisExp();
		res = a == b;
		explanation = text(a, " == ", b);	
	}
	catch (Exception e)
	{
		msg ~= text(" (Caught exception ", e, ")");
	}

	recordTestResult(res, explanation, msg, file, line, func);
	// writeln("Test ", file, "@", line, " ", msg, ": ", a, " == ", b, " ", res ? "OK" : "FAILED");
}

void AssertContains(T, V)(lazy T thisRange, lazy V containsThisElementOrRange, string msg = "", string file = __FILE__, int line = __LINE__, string func = __FUNCTION__)
{
	import std.algorithm;
    import std.range;
	bool res = false;
	string explanation = "a contains b";
	try
	{
	    auto a = thisRange();
		auto b = containsThisElementOrRange();
		res = !find(thisRange, containsThisElementOrRange).empty;
		explanation = text(a, " contains ", b);
	}
	catch (Exception e)
	{
		msg ~= text(" (Caught exception ", e, ")");
	}

	recordTestResult(res, explanation, msg, file, line, func);
	// writeln("Test ", file, "@", line, " ", msg, ": ", a, " == ", b, " ", res ? "OK" : "FAILED");
}

void AssertRangesEqual(T, V)(lazy T thisExp, lazy V isEqualToThisExp, string msg = "", string file = __FILE__, int line = __LINE__, string func = __FUNCTION__)
{
	import std.range;
	import std.array;
	bool res = false;
	string testMsg = null;
	auto app1 = appender!string;
	try
	{
		auto r1 = thisExp();
		auto r2 = isEqualToThisExp();

		static if (__traits(compiles, r1.length == r2.length))
		{
			if (r1.length != r2.length)
			{
				recordTestResult(false, text("length of ", r1, " == length of ", r2), msg ~ " " ~ func, file, line, func);
				return;
			}
		}

	    int count = 0;
	    
		app1.put("[");
	    auto app2 = appender!string;
		app2.put("[");
		
		while (!r1.empty || !r2.empty)
	    {
			if (testMsg is null)
	        {
	            if (r1.empty || r2.empty)
				    testMsg = text("length of ", r1, " != length of ", r2, ". ");
			    else if (r1.front != r2.front)
	    			testMsg = text("ranges differs at index ", count, ". ");
			}

			if (!r1.empty)
			{
				if (count != 0)
					app1.put(", ");
				app1.put(r1.front.to!string);
				r1.popFront();
	        }

			if (!r2.empty)
			{
				if (count != 0)
					app2.put(", ");
				app2.put(r2.front.to!string);
				r2.popFront();
			}
			count++;
	    }
		app1.put("]");
		app2.put("]");

		app1.put(" == ");
		app1.put(app2.data);
	}
	catch (Exception e)
	{
		msg ~= text(" (Caught exception ", e, ")");
	}
	recordTestResult(testMsg is null, testMsg ~ app1.data, msg ~ " " ~ func, file, line, func);
}

unittest
{
    struct MyInputRange
    {
        uint[] x;
        int index;

        @property uint front() { return x[index]; }
        @property bool empty() const { return index == x.length; }
        void popFront() { index++; }
    }
    
    g_RecordingOn = false;
    scope (exit) g_RecordingOn = true;

    auto r1 = MyInputRange([1]);
    auto r2 = MyInputRange([]);
    AssertRangesEqual(r1, r2);

    auto r3 = MyInputRange([1,2]);
    auto r4 = MyInputRange([1,3]);
    AssertRangesEqual(r3, r4);
}


immutable string ANSI_RED = "\x1b[31m";
immutable string ANSI_GREEN = "\x1b[32m";
immutable string ANSI_YELLOW = "\x1b[33m";
immutable string ANSI_RESET = "\x1b[0m";

void AssertIs(T,V)(lazy T thisExp, lazy V isEqualToThisExp, string msg = "", string file = __FILE__, int line = __LINE__, string func = __FUNCTION__)
{
	bool res = false;
	string explanation = "a is b";
	try
	{
		auto a = thisExp();
		auto b = isEqualToThisExp();
		res = a is b;
		explanation = text(a, " is ", b);
	}
	catch (Exception e)
	{
		msg ~= text(" (Caught exception ", e, ")");
	}		
	recordTestResult(res, explanation, msg, file, line, func);
	//	writeln("Test ", file, "@", line, " ", msg, ": ", a, " is ", b, " ", res ? ANSI_GREEN ~ "OK" ~ ANSI_RESET : ANSI_RED ~ "FAILED" ~ ANSI_RESET);
	// writeln("Test ", file, "@", line, " ", msg, ": ", a, " is ", b, " ", res ? "OK" : "FAILED");
}

void AssertIsNot(T,V)(lazy T thisExp, lazy V isEqualToThisExp, string msg = "", string file = __FILE__, int line = __LINE__, string func = __FUNCTION__)
{
	bool res = false;
	string explanation = "a is not b";
	try
	{
		auto a = thisExp();
		auto b = isEqualToThisExp();
		res = a !is b;
		explanation = text(a, " is not ", b);
	}
	catch (Exception e)
	{
		msg ~= text(" (Caught exception ", e, ")");
	}		
	recordTestResult(res, explanation, msg, file, line, func);
	//	writeln("Test ", file, "@", line, " ", msg, ": ", a, " is ", b, " ", res ? ANSI_GREEN ~ "OK" ~ ANSI_RESET : ANSI_RED ~ "FAILED" ~ ANSI_RESET);
	// writeln("Test ", file, "@", line, " ", msg, ": ", a, " is ", b, " ", res ? "OK" : "FAILED");
}
