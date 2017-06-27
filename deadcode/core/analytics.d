module deadcode.core.analytics;

import std.array;
import std.conv;
import std.datetime;
import std.net.curl;
import std.concurrency;
import std.stdio;

class Analytics
{
	//void addEvent(string category, string action, string label = null, string value = null);
	//void addtiming(string category, string variable, Duration d);
	//void addException(string description, bool isFatal);

	private
	{
		StopWatch[string] runningTimings;
	}

	void stop() {}

	void startTiming(string category, string variable)
	{
		StopWatch sw;
		sw.start();
		runningTimings[category ~ "::" ~ variable] = sw;
	}

	void stopTiming(string category, string variable)
	{
		StopWatch* sw = (category ~ "::" ~ variable) in runningTimings;
		if (sw is null)
			return;
		sw.stop();
		addTiming(category, variable, cast(Duration)sw.peek());
	}

	void addEvent(string category, string action, string label = null, string value = null)
	{
		writefln("addEvent %s %s %s %s", category, action, label, value);
	}

	void addTiming(string category, string variable, Duration d)
	{
		writefln("addTiming %s %s %s", category, variable, d);
	}

	void addException(string description, bool isFatal)
	{
		writefln("addException %s %s", description, isFatal);
	}
}

//class NullAnalytics : Analytics
//{
//    void addEvent(string category, string action, string label = null, string value = null)
//    {
//        writefln("addEvent %s %s %s %s", category, action, label, value);
//    }
//
//    void addTiming(string category, string variable, Duration d)
//    {
//        writefln("addTiming %s %s %s", category, variable, d);
//    }
//
//    void addException(string description, bool isFatal)
//    {
//        writefln("addException %s %s", description, isFatal);
//    }
//}

class GoogleAnalytics : Analytics
{
	private
	{
		enum BASEURL = "http://www.google-analytics.com/collect";
		Tid worker;
		struct BaseParams
        {
            string appName;
		    string appID;
		    string appVersion;
		    string trackingID;
		    string clientID;
        }
        BaseParams _baseParams;
		shared bool running;
	}

	this(string trackingID, string clientID, string appName, string appID, string appVersion)
	{
		_baseParams.clientID = clientID;
		_baseParams.trackingID = trackingID;
		_baseParams.appName = appName;
		_baseParams.appID = appID;
		_baseParams.appVersion = appVersion;
	}

	~this()
	{
		if (!running)
			return;
		running = false;
		worker.send("");
	}

	void spawnWorkerThread()
	{
		//void data = null;
		worker = spawn(&run, _baseParams, &running);
	}

	// void foo() {}

	override void stop()
	{
		if (!running)
			return;
		running = false;
		worker.send("");
	}

	override void addEvent(string category, string action, string label = null, string value = null)
	{
		ensureRunning();
		// writefln("addEvent %s %s %s %s", category, action, label, value);
		worker.send(category, action, label, value);
	}

	override void addTiming(string category, string variable, Duration d)
	{
		ensureRunning();
		// writefln("addTiming %s %s %s", category, variable, d.total!"msecs"());
		worker.send(category, variable, d);
	}

	override void addException(string description, bool isFatal)
	{
		ensureRunning();
		// writefln("addException %s %s", description, isFatal);
		worker.send(description, isFatal);
	}

	private void ensureRunning()
	{
		if (!running)
			spawnWorkerThread();
	}

	private static void run(BaseParams baseParams, shared(bool*) running)
	{
		auto httpClient = HTTP();
		*running = true;
		while(*running)
		{
			receive( (string category, string action, string label, string value)
					 {
						sendEvent(httpClient, baseParams, category, action, label, value);
					 },
					 (string category, string variable, Duration d)
					 {
						sendTiming(httpClient, baseParams, category, variable, d);
					 },
					 (string exDesc, bool exFatal)
					 {
						 sendException(httpClient, baseParams, exDesc, exFatal);
					 }
					 );
		}
	}

	private static void addBaseParams(BaseParams baseParams, ref Appender!string app)
	{
		//auto v = "1"; // protocol version
		//auto tid = "xxx"; // The tracking ID. The format is UA-XXXX-Y.
		//auto cid = ""; // Tracking client id UUID
		//auto t = "event"; // hit type (event, timing, exception, ...)
		//auto an = appName;
		//auto aid = appID;
		//auto av = appVersion;

		app ~= BASEURL;
		app ~= "?v=1";
		app ~= "&tid=";
		app ~= baseParams.trackingID;
		app ~= "&cid=";
		app ~= baseParams.clientID;
		app ~= "&an=";
		app ~= baseParams.appName;
		app ~= "&av=";
		app ~= baseParams.appVersion;
		app ~= "&aid=";
		app ~= baseParams.appID;
	}

	private static void sendEvent(HTTP httpClient, BaseParams baseParams, string category, string action, string label, string value)
	{
		auto app = appender!string;
		addBaseParams(baseParams, app);
		app ~= "&ec=";
		app ~= category;
		app ~= "&ea=";
		app ~= action;
		app ~= "&t=event";

		if (label !is null)
		{
			app ~= "&el=";
			app ~= label;
		}
		if (value !is null)
		{
			app ~= "&ev=";
			app ~= value;
		}

		auto data = get(app.data, httpClient);
	}

	private static void sendTiming(HTTP httpClient, BaseParams baseParams, string category, string variable, Duration d)
	{
		auto app = appender!string;
		addBaseParams(baseParams, app);
		app ~= "&t=timing";
		app ~= "&utc=";
		app ~= category;
		app ~= "&utv=";
		app ~= variable;
		app ~= "&utt=";
		app ~= d.total!"msecs"().to!string();
		auto data = get(app.data, httpClient);
	}

	private static void sendException(HTTP httpClient, BaseParams baseParams, string exDesc, bool exFatal)
	{
		auto app = appender!string;
		addBaseParams(baseParams, app);
		app ~= "&t=exception";
		app ~= "&exd=";
		app ~= exDesc;
		app ~= "&exf=";
		app ~= exFatal ? "1" : "0";
		auto data = get(app.data, httpClient);
	}

}
