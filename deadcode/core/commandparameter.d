module deadcode.core.commandparameter;

import std.string;
import std.variant;

alias CommandParameter = Algebraic!(uint, int, string, float);

struct CommandCall
{
	string name;
	CommandParameter[] arguments;
}

CommandCall createCommandCall(T...)(string name, T ts)
{	
	auto c = CommandCall(name);
	foreach (t; ts)
		c.arguments ~= CommandParameter(t);
	return c;
}

CommandParameter parse(CommandParameter typeSpecifier, string input)
{
	import std.conv;
    scope (failure)
    {
        import std.stdio;
        version (linux)
            debug writeln("Input string was ", input);
    }

	if (typeSpecifier.type() == typeid(uint))
		return CommandParameter(input.to!uint);
	if (typeSpecifier.type() == typeid(int))
		return CommandParameter(input.to!int);
	if (typeSpecifier.type() == typeid(string))
		return CommandParameter(input);
	if (typeSpecifier.type() == typeid(float))
		return CommandParameter(input.to!float);

	throw new Exception("Cannot parse command arg " ~ input ~ " into " ~ typeSpecifier.type().toString());

	//CommandParameter parsedValue = typeSpecifier.visit!( (uint p) => CommandParameter(input.to!uint),
	//                                                     (int p) => CommandParameter(input.to!int),
	//                                                     (string p) => CommandParameter(input),
	//                                                     (float p) => CommandParameter(input.to!float) );
	//return parsedValue;
}

struct CommandParameterDefinition
{
	this(CommandParameter p, string n = "", string desc = "", bool isNul = true)
	{
		parameter = p;
		name = n;
		description = desc;
        isNull = isNul;
	}

	CommandParameter parameter;
	string name;
	string description;
    bool isNull; // See CommandParameterDefinitions.paramtersAreNull
}

final class CommandParameterDefinitions
{
	CommandParameter[] parameters;
	string[] parameterNames;
	string[] parameterDescriptions;

	// The assigned value for a template command parameter is only set to specify the type.  If valueIsDefault
	// is true then the value also defines a default value of the parameter is not specified when using a command
	// with the command parameter. Otherwise it is mandatory to set the paramter.
	bool[] parametersAreNull;

	//ref CommandParameter opIndex(size_t n)
	//{
	//    return parameters[n];
	//}

    CommandParameterDefinition[] asArray() const
    {
        CommandParameterDefinition[] res;
        res.length = parameters.length;
        foreach (i; 0..parameters.length)
            res[i] = opIndex(i);
        return res;
    }

	const(CommandParameterDefinition) opIndex(size_t n) const
	{
		return CommandParameterDefinition(parameters[n], parameterNames[n], parameterDescriptions[n], parametersAreNull[n]);
	}

	@property size_t length() const pure nothrow @safe
	{
		return parameters.length;
	}

	bool isTypesMatching(CommandParameterDefinitions other) const
	{
		if (other.parameters.length != parameters.length)
			return false;

		foreach (i, ref p; parameters)
		{
			if (other.parameters[i].type() != p.type())
				return false;
		}
		return true;
	}

	bool setValues(ref CommandParameter[] toValues, CommandParameter[] fromValues)
	{
		assert(fromValues.length <= parameters.length);

		bool allSet = true;

		foreach (i, v; parameters)
		{
			if (i < fromValues.length)
			{
				if (v.type() != fromValues[i].type())
						throw new Exception(format("Cannot set command parameter of type %s to value of type %s",
										   v.type(), fromValues[i].type()));
				toValues ~= fromValues[i];
			}
			else
			{
				if (parametersAreNull[i])
				{
					allSet = false;
					break;
				}
				else
				{
					toValues ~= v;
				}
			}
		}
		return allSet;
	}

	bool parseValues(ref CommandParameter[] toValues, ref string input)
	{
		import std.range;
		bool allSet = true;

		toValues.length = parameters.length;

		foreach (i, v; parameters)
		{
			string token = munch(input, "^ \t");
            if (!token.empty)
            {
                try
                {
                    CommandParameter parsedValue = v.parse(token);
                    toValues[i] = parsedValue;
                }
                catch (Exception)
                {
                    token = null;
                }
                munch(input, " \t");
            }

			if (token.empty)
			{
				// Fill with default values
				foreach (idx; i .. parameters.length)
				{
					toValues[idx] = v;
					if (parametersAreNull[idx])
						allSet = false;
				}
				break;
			}
		}
		return allSet;
	}

	void setDefaultValue(size_t idx)
	{
		assert(idx < parameters.length);
		parametersAreNull[idx]= false;
	}

	//
	static CommandParameterDefinitions create(Args...)(Args args)
	{
		CommandParameterDefinitions res = new CommandParameterDefinitions;
		res.parameters.length = args.length;
		res.parameterNames.length = args.length;
		res.parameterDescriptions.length = args.length;
		res.parametersAreNull.length = args.length;
		foreach (i, a; args)
		{
			res.parametersAreNull[i] = true;
			static if (is(a == CommandParameterDefinition))
			{
				res.parameters[i] = a.parameter;
				res.parameterNames[i] = a.name;
				res.parameterDescriptions[i] = a.description;
			}
			else
			{
				res.parameters[i] = CommandParameter(a);
				res.parameterNames[i] = "";
				res.parameterDescriptions[i] = "";
			}
		}
		return res;
	}

    static CommandParameterDefinitions create(CommandParameterDefinition[] arr)
    {
		CommandParameterDefinitions res = new CommandParameterDefinitions;
		res.parameters.length = arr.length;
		res.parameterNames.length = arr.length;
		res.parameterDescriptions.length = arr.length;
		res.parametersAreNull.length = arr.length;
        foreach (i, elm; arr)
        {
            res.parameters[i] = elm.parameter;
            res.parameterNames[i] = elm.name;
            res.parameterDescriptions[i] = elm.description;
            res.parametersAreNull[i] = elm.isNull;
        }
        return res;
    }
}

CommandParameterDefinitions createParams(Args...)(Args args) if ( ! is(Args[0] == string[]) )
{
	return CommandParameterDefinitions.create(args);
}

CommandParameterDefinitions createParams(Args...)(string[] names, Args args)
{
	auto res = CommandParameterDefinitions.create(args);
	res.parameterNames = names;
	return res;
}

CommandParameter[] createArgs(Args...)(Args args)
{
	CommandParameter[] res;
	res.length = args.length;
	foreach (i, a; args)
	{
		res[i] = CommandParameter(a);
	}
	return res;
}

void registerCommandParameterMsgPackHandlers()()
{
    static import msgpack;
    import std.conv;

    static void commandParameterPackHandler(ref msgpack.Packer packer, ref CommandParameter param)
    {
        import std.variant;
        param.tryVisit!( (uint p) { int id = 1; packer.pack(id); packer.pack(p); },
                         (int p) { int id = 2; packer.pack(id); packer.pack(p); },
                             (string p) { int id = 3; packer.pack(id); packer.pack(p); },
                                 (float p) { int id = 4; packer.pack(id); packer.pack(p); } );
    }

    static void commandParameterUnpackHandler(ref msgpack.Unpacker u, ref CommandParameter p)
    {
        int id;
        u.unpack(id);
        switch (id)
        {
            case 1:
                uint r;
                u.unpack(r);
                p = r;
                break;
            case 2:
                int r;
                u.unpack(r);
                p = r;
                break;
            case 3:
                string r;
                u.unpack(r);
                p = r;
                break;
            case 4:
                float r;
                u.unpack(r);
                p = r;
                break;
            default:
                throw new Exception("Cannot unpack CommandParamter with type " ~ id.to!string);
        }
    }
	
	static void commandParameterDefinitionsPackHandler(ref msgpack.Packer packer, ref CommandParameterDefinitions p)
	{
		packer.pack(p.parameters);
		packer.pack(p.parameterNames);
		packer.pack(p.parameterDescriptions);
		packer.pack(p.parametersAreNull);
	}

    static void commandParameterDefinitionsUnpackHandler(ref msgpack.Unpacker packer, ref CommandParameterDefinitions p)
    {
		packer.unpack(p.parameters);
		packer.unpack(p.parameterNames);
		packer.unpack(p.parameterDescriptions);
		packer.unpack(p.parametersAreNull);	
	}

    msgpack.registerPackHandler!(CommandParameter, commandParameterPackHandler);
    msgpack.registerUnpackHandler!(CommandParameter, commandParameterUnpackHandler);

    msgpack.registerPackHandler!(CommandParameterDefinitions, commandParameterDefinitionsPackHandler);
    msgpack.registerUnpackHandler!(CommandParameterDefinitions, commandParameterDefinitionsUnpackHandler);
}
