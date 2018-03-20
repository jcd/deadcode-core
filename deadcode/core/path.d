module deadcode.core.path;

import std.file : getcwd;
import std.range.primitives : ElementEncodingType, ElementType, isInputRange;
import std.string;
import std.traits : isSomeChar, isSomeString;

public import std.path : extension, baseName, CaseSensitive, defaultExtension, dirName, driveName, expandTilde, globMatch, isAbsolute, isDirSeparator, pathSplitter, setExtension, stripDrive, stripExtension;
static import std.path;

immutable(ElementEncodingType!(ElementType!Range))[] buildPath(Range)(Range segments)
if (isInputRange!Range && isSomeString!(ElementType!Range))
{
	version (Windows)
		return std.path.buildPath(segments).tr(r"\","/");
	else
		return std.path.buildPath(segments);
}

pure @safe immutable(C)[] buildPath(C)(const(C)[][] paths...)
if (isSomeChar!C)
{
	version (Windows)
		return std.path.buildPath(paths).tr(r"\","/");
	else
		return std.path.buildPath(paths);
}

pure @trusted immutable(C)[] buildNormalizedPath(C)(const(C[])[] paths...)
{
	version (Windows)
		return std.path.buildNormalizedPath(paths).tr(r"\","/");
	else
		return std.path.buildNormalizedPath(paths);
}

pure @safe string absolutePath(string path, lazy string base = getcwd())
{
	version (Windows)
		return std.path.absolutePath(path, base).tr(r"\","/");
	else
		return std.path.absolutePath(path, base);
}

auto rootName(R)(R path)
{
	version (Windows)
		return std.path.rootName(path).tr(r"\","/");
	else
		return std.path.rootName(path);
}


auto completePath(string path)
{
	import std.algorithm;
	import std.array;
	import std.file;
	import std.string;
	import std.typecons;
	import deadcode.util.string;

	string relDirPath = path;
	string filenamePrefix;
	if (!path.empty)
	{
		auto ch = path[$-1];
		if (!isDirSeparator(ch))
		{
			relDirPath = dirName(path);
			filenamePrefix = baseName(path);
		}

		if (relDirPath == ".")
			relDirPath = "";
	}

	//auto dirPath = dirName(absolutePath(path));
	//  auto filenamePrefix = baseName(path);

	debug {
		static import std.stdio;
		version (linux)
			std.stdio.writeln(path, " ", relDirPath, " : ", filenamePrefix, " ", dirEntries(relDirPath, SpanMode.shallow));
	}

	auto r1 = dirEntries(relDirPath, SpanMode.shallow)
		.map!(a => tuple(filenamePrefix.empty ? 1.0 : baseName(a).rank(filenamePrefix), a.isDir ? tr(a.name, r"\", "/") ~ '/' : tr(a.name, r"\", "/")))
		.filter!(a => a[0] > 0.0)
		.array;
	auto r2 = r1
		.sort!((a,b) => a[0] > b[0]);
	return r2;
}