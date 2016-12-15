module deadcode.core.log;

import std.stdio;
import deadcode.core.attr;
import deadcode.core.ctx;
import deadcode.core.signals;

CtxVar!Log _globalLogger;

// Convenience property for access cached Ctx.Get!Log
@property ref CtxVar!Log log()
{
    return _globalLogger;
}

enum LogLevel : ubyte
{
    verbose,
    info,
    warning,
    error
}

interface ILog
{
    void log(LogLevel level, string message);

    void opCall(Types...)(Types msgs)
    {
        _log(LogLevel.info, msgs);
    }

    alias info = opCall;
    alias i = opCall;

    void verbose(Types...)(Types msgs)
    {
        _log(LogLevel.verbose, msgs);
    }

    alias v = verbose;

    void warning(Types...)(Types msgs)
    {
        _log(LogLevel.warning, msgs);
    }

    alias w = warning;

    void error(Types...)(Types msgs)
    {
        _log(LogLevel.error, msgs);
    }

    alias e = error;

    private void _log(Types...)(LogLevel level, Types msgs)
    {
        import std.string;
        import std.conv;
        static import std.stdio;

        static if (msgs.length == 1)
            auto fmtmsg = format(msgs[0].to!string);
        else
            auto fmtmsg = format(msgs[0].to!string, msgs[1..$]);


        version (linux)
            std.stdio.writeln("*Messages* " ~ fmtmsg);
        
        log(level, fmtmsg);
    }
}

class Log : ILog
{
    private
    {
        File _file;
    }

    mixin Signal!(string, LogLevel) onVerbose;
    mixin Signal!(string, LogLevel) onInfo;
    mixin Signal!(string, LogLevel) onWarning;
    mixin Signal!(string, LogLevel) onError;

    this(string path)
    {
        _file = File(path, "a");
    }

    this()
    {
    }

    final File getLogFile()
    {
        return _file;
    }

    void log(LogLevel level, string message)
    {
        if (_file.getFP() !is null)
        {
            _file.writeln(message);
            _file.flush();
        }
   
        final switch (level) with (LogLevel)
        {
            case verbose:
                onVerbose.emit(message, verbose);
                break;
            case info:
                onInfo.emit(message, verbose);
                break;
            case warning:
                onWarning.emit(message, warning);
                break;
            case error:
                onError.emit(message, error);
                break;
        }
	}
}
