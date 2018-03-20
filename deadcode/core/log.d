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
    void log(string area, LogLevel level, string message);

    @property 
    {
        string path();
        void path(string p);
    }

    void opCall(Types...)(Types msgs)
    {
        _log(null, LogLevel.info, msgs);
    }

    alias info = opCall;
    alias i = opCall;

	void ainfo(Types...)(string area, Types msgs)
    {
        _log(area, LogLevel.info, msgs);
    }

    void verbose(Types...)(Types msgs)
    {
        _log(null, LogLevel.verbose, msgs);
    }

    alias v = verbose;

    void warning(Types...)(Types msgs)
    {
        _log(null, LogLevel.warning, msgs);
    }

    alias w = warning;

    void error(Types...)(Types msgs)
    {
        _log(null, LogLevel.error, msgs);
    }

    alias e = error;

    private void _log(Types...)(string areaName, LogLevel level, Types msgs)
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
        
        log(areaName, level, fmtmsg);
    }
}

class Log : ILog
{
    private
    {
        File _file;
        string _path;
    }

	// (area, level, message)
    mixin Signal!(string, LogLevel, string) onVerbose;
    mixin Signal!(string, LogLevel, string) onInfo;
    mixin Signal!(string, LogLevel, string) onWarning;
    mixin Signal!(string, LogLevel, string) onError;
    mixin Signal!(string, LogLevel, string) onAllMessages;
	mixin Signal!(string) onPathChanged;

    @property 
    {
        string path()
        {
            return _path;
        }
        
        void path(string p)
        {
            if (p != _path)
            {
				auto oldPath = _path;
				_path = p;
                if (_file.isOpen)
                {
                    _file.flush();
                    _file.close();
                }
                _file = File(_path, "a");
				onPathChanged.emit(oldPath);
			}
        }
    }

    this(string path_)
    {
        path = path_;
    }

    this()
    {
    }

    final File getLogFile()
    {
        return _file;
    }

    void log(string areaName, LogLevel level, string message)
    {
        if (_file.isOpen)
        {
            _file.writeln(message);
            _file.flush();
        }
   
        final switch (level) with (LogLevel)
        {
            case verbose:
                onVerbose.emit(areaName, verbose, message);
                break;
            case info:
                onInfo.emit(areaName, info, message);
                break;
            case warning:
                onWarning.emit(areaName, warning, message);
                break;
            case error:
                onError.emit(areaName, error, message);
                break;
        }
        onAllMessages.emit(areaName, level, message);
	}
}
