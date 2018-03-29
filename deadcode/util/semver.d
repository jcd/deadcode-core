module deadcode.util.semver;

import deadcode.test;
mixin registerUnittests;

struct SemanticVersion
{
    import std.algorithm;

    // http://semver.org/
    //
    // Format:
    // major.minor.patch-prerelease1.prereleaseN+build1.buildN
    //
    // Examples:
    // 1.2
    // 0.13
    // 1.0-beta2 
    // 1.0-beta2.first
    // 1.0-2.first.42-foo.Third-9.fourth+1.2-Muh.3.Bar-22-fd89.5.6.7.8.foo
    // 1.4.2-alpha1+152345
    //
    int major;
    int minor;
    int patch;
    string[] preRelease;
    string[] build;

    this(int ma, int mi, int pa)
    {
        major = ma;
        minor = mi;
        patch = pa;
    }


    version (unittest)
    private this(string s)
    {
        this = parse(s);
    }

    static SemanticVersion parse(string s, bool* success = null)
    {
        import std.conv;
        import std.exception;
        import std.regex;
        import std.string;

        SemanticVersion r = SemanticVersion();

        auto m = matchFirst(s, r"^(?P<major>\d+)\.(?P<minor>\d+)(?:\.(?P<patch>[^-+]+))?(?:-(?P<prerelease>[-0-9a-zA-Z\.]+))?(?:\+(?P<build>[-0-9a-zA-Z\.]+))?$");

        if (m.empty)
        {
            if (success)
                *success = false;
            return r;
        }

        r.major = m["major"].to!int;
        r.minor = m["minor"].to!int;
        r.patch = m["patch"].length ? m["patch"].to!int : 0;

        string preRelStr = m["prerelease"];
        if (preRelStr.length)
        {
            auto preRelToks = preRelStr.split('.');
            bool check = preRelToks.all!"!a.empty";
            if (!check)
            {
                if (success)
                    *success = false;
                return r;
            }
            r.preRelease = preRelToks;
        }

        string buildStr = m["build"];
        if (buildStr.length)
        {
            auto buildToks = buildStr.split('.');
            bool check = buildToks.all!"!a.empty";
            if (!check)
            {
                if (success)
                    *success = false;
                return r;
            }
            r.build = buildToks;
        }

        if (success)
            *success = true;
        return r;
    }

    ///
    unittest
    {
        import std.conv;
        Assert(SemanticVersion("0.1") == SemanticVersion(0, 1, 0), SemanticVersion("0.1").to!string);
        auto s1 = SemanticVersion(0, 1, 4);
        s1.build ~= "build2";
        Assert(SemanticVersion("0.1.4+build2") == s1, SemanticVersion("0.1.4-1+build2").to!string);
    }

    /**
    Returns: -1 if other has precedence, 1 if this has precedence and 0 if equal
    */
    int precedence(SemanticVersion other)
    {
        import std.ascii;
        import std.conv;
        if (major < other.major)
            return -1;
        else if (major > other.major)
            return 1;

        if (minor < other.minor)
            return -1;
        else if (minor > other.minor)
            return 1;

        if (patch < other.patch)
            return -1;
        else if (patch > other.patch)
            return 1;

        // Special case for empty preRelease
        if (preRelease.length == 0)
            return other.preRelease.length == 0 ? 0 : 1;
        else if (other.preRelease.length == 0)
            return -1;

        // Compare only prerelase. Build part is not used for precedence check.
        // Compare pre release toks numerically if possible else alphabetically.
        // Comparing alphabetically is done in case both tokens cannot be converted entirely to a number.
        size_t minCommonSize = preRelease.length > other.preRelease.length ? other.preRelease.length : preRelease.length;
        
        foreach (idx; 0..minCommonSize)
        {
            string thisTok = preRelease[idx];
            string otherTok = other.preRelease[idx];
            
            bool thisTokIsNum = thisTok.to!dstring.all!((a) => isDigit(a));
            bool otherTokIsNum = otherTok.to!dstring.all!((a) => isDigit(a));
            
            bool numCmp = thisTokIsNum && otherTokIsNum;
            if (numCmp)
            {
                uint thisNum = thisTok.to!uint;
                uint otherNum = otherTok.to!uint;

                if (thisNum < otherNum)
                    return -1;
                else if (thisNum > otherNum)
                    return 1;
            }
            else if (thisTokIsNum)
            {
                return -1; // non-numeric is always higher precedence that numeric
            }
            else if (otherTokIsNum)
            {
                return 1; // non-numeric is always higher precedence that numeric
            }
            else
            {
                if (thisTok < otherTok)
                    return -1;
                else if (thisTok > otherTok)
                    return 1;
            }
        }

        if (preRelease.length == other.preRelease.length)
            return 0;

        return preRelease.length < other.preRelease.length ? -1 : 1;
    }

    ///
    version (unittest)
    @("Testing SemanticVersion")
    unittest
    {
        import std.conv;
        import unit_threaded;
        SemanticVersion("1.0-foo").precedence(SemanticVersion("1.0")).shouldEqual(-1);
        SemanticVersion("1.1").precedence(SemanticVersion("2.1")).shouldEqual(-1);

/*
        Assert(-1, SemanticVersion("1.0-foo").precedence(SemanticVersion("1.0")));
        Assert(-1, SemanticVersion("1.1").precedence(SemanticVersion("2.1")));
        Assert(1, SemanticVersion("2.1").precedence(SemanticVersion("1.1")));
        Assert(-1, SemanticVersion("1.1.1").precedence(SemanticVersion("1.1.2")));
        Assert(1, SemanticVersion("1.1.2").precedence(SemanticVersion("1.1.1")));
        Assert(0, SemanticVersion("0.1").precedence(SemanticVersion("0.1")));
        Assert(-1, SemanticVersion("0.1").precedence(SemanticVersion("0.2")));
        Assert(1, SemanticVersion("0.2").precedence(SemanticVersion("0.1")));
        Assert(1, SemanticVersion("0.2").precedence(SemanticVersion("0.1")));
        Assert(1, SemanticVersion("0.1").precedence(SemanticVersion("0.1-beta")));
        Assert(-1, SemanticVersion("0.1-alpha").precedence(SemanticVersion("0.1-beta")), SemanticVersion("0.1-alpha").to!string ~ SemanticVersion("0.1-beta").to!string);
        Assert(0, SemanticVersion("0.1-alpha+24.12").precedence(SemanticVersion("0.1-alpha")), SemanticVersion("0.1-alpha+24.12").to!string ~ SemanticVersion("0.1-alpha").to!string);
        Assert(1, SemanticVersion("0.1-1.2").precedence(SemanticVersion("0.1-1")), SemanticVersion("0.1-1.2").to!string ~ SemanticVersion("0.1-1").to!string);
        Assert(1, SemanticVersion("0.1-1a").precedence(SemanticVersion("0.1-1")));
        Assert(1, SemanticVersion("0.1-2").precedence(SemanticVersion("0.1-1")));
        Assert(-1, SemanticVersion("0.1-1").precedence(SemanticVersion("0.1-2")));
        Assert(-1, SemanticVersion("0.1-1").precedence(SemanticVersion("0.1-2a")));
        Assert(1, SemanticVersion("0.1-b").precedence(SemanticVersion("0.1-a")));

        bool ok;
        parse("0.1", &ok);  
        Assert(ok);

        parse("invalid", &ok);  
        Assert(!ok);

        parse("0.1-3..4", &ok);  
        Assert(!ok);

        parse("0.1-3.4+4..4", &ok);  
        Assert(!ok);
        */
    }
}
