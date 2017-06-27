module deadcode.test.testserver;

import std.concurrency;
import std.conv;
import std.stdio;
import std.range;
import std.process : environment;
import std.file : deleteme;
import std.path : buildPath;

import std.socket : Address, InternetAddress, INADDR_LOOPBACK, Socket, TcpSocket;

struct HTTPTestServer
{
    @property string addr() { return _addr; }

	static HTTPTestServer start()
	{
		auto tid = spawn(&HTTPTestServer.loop);
		auto addr = receiveOnly!string();
		return HTTPTestServer(tid, addr);
	}

	void stop()
	{
		tid.send(false);
	}

    void handle(void function(Socket s) dg)
    {
        tid.send(dg);
    }

	void handle(string ReplyString)()
	{
		tid.send( function(Socket s) {
			auto r = recvTestReq(s);
			s.send(httpTestOK(ReplyString));
		});
	}

private:
	Tid tid;
	string _addr;

    static void loop()
    {
		auto sock = new TcpSocket;
		sock.bind(new InternetAddress(INADDR_LOOPBACK, InternetAddress.PORT_ANY));
		sock.listen(1);

		ownerTid.send(sock.localAddress.toString());

		bool running = true;

		alias Handler = void function(Socket s);
		
		Handler handler;

        try while (running)
        {
            try
			{
                receive( (Handler h) {
										handler = h;
									},
									(bool f) { running = false; }
								   );
			}
            catch (OwnerTerminated)
                return;
			
			if (running)
				handler((cast()sock).accept);
        }
        catch (Throwable e)
        {
            import core.stdc.stdlib : exit, EXIT_FAILURE;
            stderr.writeln(e);
            exit(EXIT_FAILURE);
        }
    }
}

struct HTTPTestRequest(T)
{
    string hdrs;
    immutable(T)[] bdy;
}

HTTPTestRequest!T recvTestReq(T=char)(Socket s)
{
    import std.algorithm;
	import std.regex;

	ubyte[1024] tmp=void;
    ubyte[] buf;

    while (true)
    {
        auto nbytes = s.receive(tmp[]);
        assert(nbytes >= 0);

        immutable beg = buf.length > 3 ? buf.length - 3 : 0;
        buf ~= tmp[0 .. nbytes];
        auto bdy = buf[beg .. $].find(cast(ubyte[])"\r\n\r\n");
        if (bdy.empty)
            continue;

        auto hdrs = cast(string)buf[0 .. $ - bdy.length];
        bdy.popFrontN(4);
        // no support for chunked transfer-encoding
        if (auto m = hdrs.matchFirst(ctRegex!(`Content-Length: ([0-9]+)`, "i")))
        {
            import std.uni : asUpperCase;
            if (hdrs.asUpperCase.canFind("EXPECT: 100-CONTINUE"))
                s.send(httpContinue);

            size_t remain = m.captures[1].to!size_t - bdy.length;
            while (remain)
            {
                nbytes = s.receive(tmp[0 .. min(remain, $)]);
                assert(nbytes >= 0);
                buf ~= tmp[0 .. nbytes];
                remain -= nbytes;
            }
        }
        else
        {
            assert(bdy.empty);
        }
        bdy = buf[hdrs.length + 4 .. $];
        return typeof(return)(hdrs, cast(immutable(T)[])bdy);
    }
}

string httpTestOK(string msg)
{
	return "HTTP/1.1 200 OK\r\n" ~
        "Content-Type: text/plain\r\n" ~
        "Content-Length: " ~ msg.length.to!string ~ "\r\n" ~
        "\r\n"~
        msg;
}

string httpTestOK()
{
    return "HTTP/1.1 200 OK\r\n" ~
        "Content-Length: 0\r\n" ~
        "\r\n";
}

string httpTestNotFound()
{
    return "HTTP/1.1 404 Not Found\r\n" ~
        "Content-Length: 0\r\n" ~
        "\r\n";
}

private enum httpContinue = "HTTP/1.1 100 Continue\r\n\r\n";

unittest
{
	import deadcode.test;
	import std.net.curl;

    AssertContains(httpTestOK(), "200 OK");
    AssertContains(httpTestNotFound(), "404 Not Found");

	auto s = HTTPTestServer.start();
	
	// Test handler before request
	s.handle!"Foo"();
	Assert(get(s.addr) == "Foo");
	
	// Test request before handler
	auto r = byChunkAsync(s.addr);
	s.handle((Socket s) {
		auto r = recvTestReq(s);
		s.send(httpTestOK("Bar"));
	});

	Assert(!r.empty);
	Assert(r.front == "Bar");

	// Test request before handler
	r = byChunkAsync(s.addr);
	s.handle((Socket s) {
		auto r = recvTestReq(s);
		s.send(httpTestOK(""));
	});

	Assert(r.empty);

    s.stop();
}
