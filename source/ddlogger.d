/// Logging facility.
///
/// Inspired by Apache log4net, without the hierarchy.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module ddlogger;

import core.sync.rwmutex;

import std.conv;
import std.datetime;
import std.datetime.stopwatch;
import std.format;
import std.stdio;

/// Log level used on a per-message basis.
///
/// The higher the level, the more verbose the logger will be. As in,
/// "give me more information".
enum LogLevel
{
    /// Silence. Appender is disabled.
    none,
    
    /// When the execution of the entire program cannot continue.
    critical,
    /// When a specific action resulted in an error.
    error,
    /// When a specific action can continue, but its setting was not optimal.
    warning,
    /// Informational message.
    info,
    /// Debugging messages.
    debugging,
    /// Information dumps and traces.
    trace,
    
    /// Include every log message possible.
    all,
}

/// Log message given to all appenders.
struct LogMessage
{
    /// Log level.
    LogLevel level;
    /// System time.
    SysTime time;
    /// Time since startup.
    long usecs;
    /// Formatted text.
    const(char)[] text;
    /// Module.
    const(char)[] mod;
    /// Line.
    int line;
}

/// Get the name of a level.
///
/// This excludes "none".
/// Params: level = LogLevel value.
/// Returns: Name, like "CRITICAL".
string logLevelName(LogLevel level)
{
    static immutable string[6] leveltable = [
        "CRITICAL",
        "ERROR",
        "WARNING",
        "INFO",
        "DEBUG",
        "TRACE",
    ];
    size_t idx = level-1;
    return idx < leveltable.length ? leveltable[idx] : "???";
}
unittest
{
    assert(logLevelName(LogLevel.critical));
    assert(logLevelName(LogLevel.error));
    assert(logLevelName(LogLevel.warning));
    assert(logLevelName(LogLevel.info));
    assert(logLevelName(LogLevel.debugging));
    assert(logLevelName(LogLevel.trace));
    assert(logLevelName(cast(LogLevel)-1));
}

/// Main interface for implementing and appender.
abstract class Appender
{
    /// Set the log level to this appender.
    /// Params: level = New log level for all new messages.
    void setLogLevel(LogLevel level)
    {
        loglevel = level;
    }
    /// Get the currently set log level of this appender.
    /// Returns: Log level.
    LogLevel getLogLevel()
    {
        return loglevel;
    }

    /// Set log level override for a specific module.
    ///
    /// Uses hierarchical prefix matching: setting a level for "myapp.rendering"
    /// also applies to "myapp.rendering.opengl", "myapp.rendering.vulkan", etc.,
    /// unless they have their own override.
    ///
    /// Params:
    ///     mod = Module path.
    ///     level = New log level.
    void setModuleLevel(const(char)[] mod, LogLevel level)
    {
        modlevels[mod] = level;
    }

    /// Remove a module level override.
    /// Params: mod = Module path.
    void clearModuleLevel(const(char)[] mod)
    {
        modlevels.remove(mod);
    }

    /// Get the effective log level for a given module name.
    ///
    /// Checks for an exact module match first, then walks up the
    /// hierarchy (e.g. "a.b.c" -> "a.b" -> "a") looking for a prefix match.
    /// Falls back to the appender's default level.
    ///
    /// Params: mod = Module path.
    /// Returns: Log level.
    LogLevel getEffectiveLevel(const(char)[] mod)
    {
        // Exact match
        if (LogLevel *p = mod in modlevels)
            return *p;

        // Walk up the hierarchy
        for (const(char)[] m = mod; m.length > 0; )
        {
            import std.string : lastIndexOf;
            ptrdiff_t idx = lastIndexOf(m, '.');
            if (idx < 0) break;
            m = m[0 .. idx];
            if (LogLevel *p = m in modlevels)
                return *p;
        }

        return loglevel;
    }

    void log(ref LogMessage message);

private:
    LogLevel loglevel;
    LogLevel[const(char)[]] modlevels;
}

/// Implements a logger that prints logs to the process's stderr stream.
class ConsoleAppender : Appender
{
    this()
    {
    }
    
    override
    void log(ref LogMessage message)
    {
        enum second_us = 1_000_000;
        long secs = message.usecs / second_us;
        long frac = message.usecs % second_us;
        // NOTE: 999,999 seconds is 277,8 Hours, so 6 digits is okay
        // NOTE: stderr is not buffered by default (vs. stdout/stdin)
        with (message)
        stderr.writefln("[%6d.%06d] %-8s [%s:%d] %s",
            secs, frac, logLevelName(level),
            mod, line,
            text);
    }
}

/// Implements a logger that prints logs to a file.
class FileAppender : Appender
{
    File file;
    
    this(string path)
    {
        file = File(path, "a");
    }
    
    override
    void log(ref LogMessage message)
    {
        // 2024-02-06T10:26:23.0468545
        with (message)
        file.writefln("%-27s %-8s [%s:%d] %s",
            time.toISOExtString(),
            logLevelName(level),
            mod, line, text);
        file.flush();
    }
}

// TODO: MemoryAppender with entry limit in ctor, defaulting to size_t.max

private __gshared
{
    // MUST be a plain GC slice, not std.container.Array. Appenders are GC
    // class instances. Array keeps them in malloc'd memory where the GC doesn't
    // scan, so under heavy logging a collection frees them and the next
    // foreach here derefs a dangling object, it leads to a SIGSEGV.
    // A __gshared slice is a GC root, which keeps them alive.
    //
    // No need to optimize this.
    Appender[] appenders;
    StopWatch watch;
    ReadWriteMutex rwmtx;
}

shared static this()
{
    watch.start();
    rwmtx = new ReadWriteMutex();
}

/// Set log level to all appenders.
/// Params: level = New log level.
void logSetLevel(LogLevel level)
{
    rwmtx.writer.lock();
    scope(exit) rwmtx.writer.unlock();
    foreach (appender; appenders)
        appender.setLogLevel(level);
}

/// Set module log level override on all appenders.
/// Params:
///     mod = Module name (hierarchical prefix match).
///     level = New log level for this module. Use LogLevel.none to mute.
void logSetModuleLevel(const(char)[] mod, LogLevel level)
{
    rwmtx.writer.lock();
    scope(exit) rwmtx.writer.unlock();
    foreach (appender; appenders)
        appender.setModuleLevel(mod, level);
}

/// Add an appender to the list.
/// Params: appender = Newly created appender.
void logAddAppender(Appender appender)
{
    rwmtx.writer.lock();
    scope(exit) rwmtx.writer.unlock();
    appenders ~= appender;
}

// Function template will make the target binary bigger but it is the
// only sane way to deal with format() and variadic parameters for it...
private
void logt(A...)(LogLevel level, string mod, int line, const(char)[] fmt, A args)
{
    if (appenders.length == 0) return;

    rwmtx.reader.lock();
    scope(exit) rwmtx.reader.unlock();

    LogMessage msg = void;
    bool prepped;
    foreach (appender; appenders)
    {
        // Do not bother if the appender's effective level is too low against requested level
        if (appender.getEffectiveLevel(mod) < level)
            continue;
        
        // At least one appender has the required level, init message (lazy method)
        if (prepped == false)
        {
            Duration since = watch.peek();
            SysTime time = Clock.currTime(); // NOTE: takes ~500 µs on Windows
            msg = LogMessage(level,
                time,
                since.total!"usecs"(),
                format(fmt, args),
                mod,
                line);
            prepped = true;
        }
        
        // Send message to appender
        appender.log(msg);
    }
}

void logCritical(A...)(string fmt, A args, string MODULE = __MODULE__, int LINE = __LINE__)
{
    logt(LogLevel.critical, MODULE, LINE, fmt, args);
}
void logError(A...)(string fmt, A args, string MODULE = __MODULE__, int LINE = __LINE__)
{
    logt(LogLevel.error, MODULE, LINE, fmt, args);
}
void logWarn(A...)(string fmt, A args, string MODULE = __MODULE__, int LINE = __LINE__)
{
    logt(LogLevel.warning, MODULE, LINE, fmt, args);
}
void logInfo(A...)(string fmt, A args, string MODULE = __MODULE__, int LINE = __LINE__)
{
    logt(LogLevel.info, MODULE, LINE, fmt, args);
}
void logDebugging(A...)(string fmt, A args, string MODULE = __MODULE__, int LINE = __LINE__)
{
    logt(LogLevel.debugging, MODULE, LINE, fmt, args);
}
void logTrace(A...)(string fmt, A args, string MODULE = __MODULE__, int LINE = __LINE__)
{
    logt(LogLevel.trace, MODULE, LINE, fmt, args);
}

unittest
{
    // Define custom appender
    class UnittestAppender : Appender
    {
        int count;
        
        LogMessage lastmsg;
        
        override
        void log(ref LogMessage message)
        {
            ++count;
            lastmsg = message;
        }
    }
    
    // Create new appender
    scope app = new UnittestAppender();
    app.setLogLevel(LogLevel.warning);
    assert(app.getLogLevel() == LogLevel.warning);
    assert(app.count == 0);
    
    // Add it to global list
    logAddAppender(app);
    assert(appenders.length == 1);
    
    // Set level to all (including ours)
    logSetLevel(LogLevel.all);
    assert(app.getLogLevel() == LogLevel.all);
    
    // Trace message
    logTrace("Here's a number: %d", 42);
    assert(app.lastmsg.mod == __MODULE__);
    assert(app.lastmsg.line);
    assert(app.lastmsg.text == "Here's a number: 42");
    assert(app.lastmsg.level == LogLevel.trace);
    assert(app.lastmsg.usecs);
    assert(app.lastmsg.time.day);
    assert(app.count == 1);
    
    // Set new level
    logSetLevel(LogLevel.warning);
    assert(app.getLogLevel() == LogLevel.warning);
}

unittest
{
    class CountAppender : Appender
    {
        int count;
        override void log(ref LogMessage message) { ++count; }
    }

    // Module level filtering
    scope app = new CountAppender();
    app.setLogLevel(LogLevel.all);

    // Mute a specific module
    app.setModuleLevel("noisy.module", LogLevel.none);
    assert(app.getEffectiveLevel("noisy.module") == LogLevel.none);

    // Hierarchical: child inherits parent override
    app.setModuleLevel("myapp.rendering", LogLevel.error);
    assert(app.getEffectiveLevel("myapp.rendering") == LogLevel.error);
    assert(app.getEffectiveLevel("myapp.rendering.opengl") == LogLevel.error);
    assert(app.getEffectiveLevel("myapp.rendering.vulkan") == LogLevel.error);

    // Unrelated module falls back to default
    assert(app.getEffectiveLevel("myapp.network") == LogLevel.all);

    // More specific override wins over parent
    app.setModuleLevel("myapp.rendering.opengl", LogLevel.trace);
    assert(app.getEffectiveLevel("myapp.rendering.opengl") == LogLevel.trace);
    assert(app.getEffectiveLevel("myapp.rendering.vulkan") == LogLevel.error);

    // clearModuleLevel removes override
    app.clearModuleLevel("myapp.rendering.opengl");
    assert(app.getEffectiveLevel("myapp.rendering.opengl") == LogLevel.error);
    app.clearModuleLevel("myapp.rendering");
    assert(app.getEffectiveLevel("myapp.rendering.opengl") == LogLevel.all);
}