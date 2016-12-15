module deadcode.util.letassign;

// by thedaemon : https://bitbucket.org/infognition/dstuff/src/97cef6d4a043?at=default
import std.typecons, std.typetuple, std.range, std.exception;
//version = chatty; // print stuff on stdout in unittests. comment this out to make them silent
version(chatty) import std.stdio;

alias pointerOf(T) = T*;
template sameTypes(Ts...) {
    static if (Ts.length <= 1) enum sameTypes = true;
           else                enum sameTypes = is(Ts[0]==Ts[1]) && sameTypes!(Ts[1..$]);
}

auto let(Ts...)(ref Ts vars) {
    struct Let {
        staticMap!(pointerOf, Ts) pnts;

        this(ref Ts vars) {
            foreach(i, t; Ts) 
                pnts[i] = &vars[i];			
        }

        void opAssign( Tuple!Ts xs ) {
            foreach(i, t; Ts) 
                *pnts[i] = xs[i];
        }

        static if (sameTypes!Ts) {
            import std.conv : text;
            void opAssign(Ts[0][] xs) { // redundant but more effective 
                enforce(xs.length == Ts.length, "let (...) = ...: array must have " ~ Ts.length.text ~ " elements.");
                foreach(i, t; Ts) 
                    *pnts[i] = xs[i];
            }

            void opAssign(R)(R xs) if (isInputRange!R && is(ElementType!R == Ts[0])) {
                static if (hasLength!R) {					
                    enforce(xs.length >= Ts.length, "let (...) = ...: range must have at least " ~ Ts.length.text ~ " elements.");
                }
                foreach(i, t; Ts) {
                    enforce(!xs.empty, "let (...) = ...: range must have at least " ~ Ts.length.text ~ " elements.");
                    *pnts[i] = xs.front;
                    xs.popFront();
                }
            }

            void opIndexAssign(R)(R xs) if (isInputRange!R && is(ElementType!R == Ts[0])) {
                foreach(i, t; Ts) {
                    if(xs.empty) return;
                    *pnts[i] = xs.front;
                    xs.popFront();
                }
            }
        }
    }

    return Let(vars);
}

R into(R, Ts...)(Tuple!Ts xs, scope R delegate(Ts) f) {
    return f(xs.expand);
}

//the rest is just tests..
static assert(sameTypes!(int, int, int));
static assert(!sameTypes!(int, bool, int));
static assert(!sameTypes!(int, bool, string));

version(unittest) 
auto getTuple(int x) {
    return tuple(x, "bottles");
}

unittest { //with tuple
    int n; string what;
    let (n, what) = getTuple(99);
    version(chatty) writeln("n=", n, " what=", what);
    assert(n==99); assert(what=="bottles");
    version(chatty) writeln("let (...) = tuple ok");
}

unittest { //with array
    int n, k, i; 
    let (n, k, i) = [3,4,5];
    version(chatty) writeln("n=", n, " k=", k, " i=", i);
    assert(n==3); assert(k==4); assert(i==5);

    assertThrown( let (n, k, i) = [3,5] ); //throw if not enough data
    
    // let (...)[] = ... uses available data and doesn't throw if there are not enough elements
    n = 1; k = 1; i = 1;
    let (n, k, i)[] = [3,5];
    assert(n==3); assert(k==5); assert(i==1);

    let (n, k, i) = tuple(10, 20, 30);
    version(chatty) writeln("n=", n, " k=", k, " i=", i);
    assert(n==10); assert(k==20); assert(i==30);
    version(chatty) writeln("let (...) = array ok");
}

unittest { //with range
    import std.algorithm, std.conv;
    string[] argv = ["prog", "100", "200"];
    int x, y;
    let (x,y) = argv[1..$].map!(to!int);
    version(chatty) writeln("x=", x, " y=", y);
    assert(x==100); assert(y==200);

    assertThrown( let (x,y) = argv[2..$].map!(to!int) ); //throw if not enough data

    // let (...)[] = ... uses available data and doesn't throw if there are not enough elements
    x = 1; y = 1;
    let (x,y)[] = argv[2..$].map!(to!int); 
    assert(x==200);	assert(y==1);
    version(chatty) writeln("let (...) = range ok");
}

unittest { //into
    version(chatty) tuple(99, "bottles").into( (int n, string s) => writeln(n, " ", s) );
    int x = getTuple(10).into( (int n, string s) => n + s.length );
    assert(x==17);
    version(chatty) writeln("into ok");
}
