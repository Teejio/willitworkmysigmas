package tea;

import ex.*;

import haxe.Exception;
import haxe.Timer;

import teaBase.*;
import teaBase.Expr;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

import tea.backend.*;

using StringTools;

/**
	Sugar containing several useful information about function calls.
**/
typedef Tea =
{
	#if sys
	/**
		Tea's file name. Will be null if the tea is not from a file. 
		
		Not available on JavaScript.
	**/
	public var ?fileName(default, null):String;
	#end
	
	/**
		If call's been successful or not. 
	**/
	public var succeeded(default, null):Bool;

	/**
		Function's name that has been called. 
	**/
	public var calledFunction(default, null):String;

	/**
		Function's return value. Will be if null if there is no value.
	**/
	public var returnValue(default, null):Null<Dynamic>;

	/**
		Errors in this call. Will be empty if there are not any.
	**/
	public var exceptions(default, null):Array<TeaException>;

	/**
		How many seconds it took to call the this function.

		It will be -1 if call's been unsuccessful.
	**/
	public var lastReportedTime(default, null):Float;
}

/**
	A nice object to brew some tea with!
**/
@:structInit
@:access(teaBase.Interp)
@:access(teaBase.Parser)
@:access(teaBase.Tools)
@:keepSub
class SScript
{
	/**
		If not null, assigns all teas to check or ignore type declarations.
	**/
	public static var defaultTypeCheck(default, set):Null<Bool> = true;

	/**
		If not null, switches traces from `doString` and `new()`. 
	**/
	public static var defaultDebug(default, set):Null<Bool> = null;

	/**
		Variables in this map will be set to every Tea instance. 
	**/
	public static var globalVariables:TeaGlobalMap = new TeaGlobalMap();

	/**
		Variables in this map will be set to every Tea instance.
		
		Variables in this map CANNOT be changed in teas, unless you remove it from the map.
	**/
	public static var strictGlobalVariables:TeaStrictGlobalMap = new TeaStrictGlobalMap();
	
	/**
		Every brewed Tea will be mapped to this map. 
	**/
	public static var global(default, null):Map<String, SScript> = [];
	
	static var IDCount(default, null):Int = 0;

	static var BlankReg(get, never):EReg;
	
	/**
		This is a custom origin you can set.

		If not null, this will act as file path.
	**/
	public var customOrigin(default, set):String;

	/**
		Tea's own return value.
		
		This is not to be messed up with function's return value.
	**/
	public var returnValue(default, null):Null<Dynamic>;

	/**
		ID for this tea, used for teas with no script file.
	**/
	public var ID(default, null):Null<Int> = null;

	/**
		Whether the type checker should be enabled.
	**/
	public var typeCheck:Bool = false;

	/**
		Reports how many seconds it took to execute this tea. 

		It will be -1 if it failed to execute.
	**/
	public var lastReportedTime(default, null):Float = -1;

	/**
		Used in `set`. If a class is set in this tea while being in this array, an exception will be thrown.
	**/
	public var notAllowedClasses(default, null):Array<Class<Dynamic>> = [];

	/**
		Use this to access to interpreter's variables!
	**/
	public var variables(get, never):Map<String, Dynamic>;

	/**
		Main interpreter and executer. 

		Do not use `interp.variables.set` to set variables!
		Instead, use `set`.
	**/
	public var interp(default, null):Interp;

	/**
		An unique parser for the tea to parse strings.
	**/
	public var parser(default, null):Parser;

	/**
		The script to execute. Gets set automatically if you brew a `new` Tea.
	**/
	public var script(default, null):String = "";

	/**
		This variable tells if this tea is active or not.

		Set this to false if you do not want your tea to get executed!
	**/
	public var active:Bool = true;

	/**
		This string tells you the path of your script file as a read-only string.
	**/
	public var scriptFile(default, null):String = "";

	/**
		If true, enables error traces from the functions.
	**/
	public var traces:Bool = false;

	/**
		If true, enables some traces from `doString` and `new()`.
	**/
	public var debugTraces:Bool = false;

	/**
		Latest error in this script in parsing. Will be null if there aren't any errors.
	**/
	public var parsingException(default, null):TeaException;

	/**
		"Class" path of this tea. Doesn't actually represent a class, it's only here for static variables.

		Teas cannot have same class paths, they must be all different. 

		Automatically gets changed when you use `class` in tea.
	**/
	public var classPath(get, null):String;

	/**
		Package path of this tea. Gets set automatically when you use `package`.
	**/
	public var packagePath(get, null):String = "";

	@:deprecated("parsingExceptions are deprecated, use parsingException instead")
	var parsingExceptions(get, never):Array<Exception>;

	@:noPrivateAccess var _destroyed(default, null):Bool;

	/**
		Brews a new Tea.

		@param scriptPath The script path or the script itself.
		@param Preset If true, SScript will set some useful variables to interp. Override `preset` to customize the settings.
		@param startExecute If true, script will execute itself. If false, it will not execute.	
	**/
	public function new(?scriptPath:String = "", ?preset:Bool = true, ?startExecute:Bool = true)
	{
		var time = Timer.stamp();

		if (defaultTypeCheck != null)
			typeCheck = defaultTypeCheck;
		if (defaultDebug != null)
			debugTraces = defaultDebug;

		interp = new Interp();
		interp.setScr(this);

		parser = new Parser();

		if (preset)
			this.preset();

		for (i => k in globalVariables)
		{
			if (i != null)
				set(i, k);
		}

		for (i => k in strictGlobalVariables)
		{
			if (i != null)
				interp.finalVariables.set(i, k);
		}

		try 
		{
			doFile(scriptPath);
			if (startExecute)
				execute();
			lastReportedTime = Timer.stamp() - time;

			if (debugTraces && scriptPath != null && scriptPath.length > 0)
			{
				if (lastReportedTime == 0)
					trace('Tea brewed instantly (0 seconds)');
				else 
					trace('Tea brewed in ${lastReportedTime} seconds');
			}
		}
		catch (e)
		{
			lastReportedTime = -1;
		}
	}

	/**
		Executes this tea once. Must be called once to get classes and functions working.
	**/
	public function execute():Void
	{
		if (_destroyed)
			return;

		if (interp == null || !active)
			return;

		var origin:String = {
			if (customOrigin != null && customOrigin.length > 0)
				customOrigin;
			else if (scriptFile != null && scriptFile.length > 0)
				scriptFile;
			else 
				"SScript";
		};

		if (script != null && script.length > 0)
		{
			resetInterp();
			
			try 
			{
				var expr:Expr = parser.parseString(script, origin);
				var r = interp.execute(expr);
				returnValue = r;
			}
			catch (e) 
			{
				parsingException = e;				
				returnValue = null;
			}
		}
	}

	/**
		Sets a variable to this tea. 

		If `key` already exists, it will be replaced.
		@param key Variable name.
		@param obj The object to set.
		@param setAsFinal Whether if set the object as final. If set as final, 
		object will act as a final variable and cannot be changed in script.
		@return Returns this instance for chaining.
	**/
	public function set(key:String, obj:Dynamic, ?setAsFinal:Bool = false):SScript
	{
		if (_destroyed)
			return null;

		if (obj != null && (obj is Class) && notAllowedClasses.contains(obj))
			throw 'Tried to set ${Type.getClassName(obj)} which is not allowed.';

		function setVar(key:String, obj:Dynamic):Void
		{
			if (key == null)
				return;

			if (Tools.keys.contains(key))
				throw '$key is a keyword and it cannot be set';

			if (!active)
				return;

			if (interp == null || !active)
			{
				if (traces)
				{
					if (interp == null)
						trace("This tea is unusable!");
					else
						trace("This tea is not active!");
				}
			}
			else
			{
				if (setAsFinal)
					interp.finalVariables[key] = obj;
				
				else 
					switch Type.typeof(obj) {
						case TFunction | TClass(_) | TEnum(_): 
							interp.finalVariables[key] = obj;
						case _:
							interp.variables[key] = obj;
					}
			}
		}

		setVar(key, obj);
		return this;
	}

	/**
		This is a helper function to set classes easily.
		For example; if `cl` is `sys.io.File` class, it'll be set as `File`.
		@param cl The class to set.
		@return this instance for chaining.
	**/
	public function setClass(cl:Class<Dynamic>):SScript
	{
		if (_destroyed)
			return null;
		
		if (cl == null)
		{
			if (traces)
			{
				trace('Class cannot be null');
			}

			return null;
		}

		var clName:String = Type.getClassName(cl);
		if (clName != null)
		{
			var splitCl:Array<String> = clName.split('.');
			if (splitCl.length > 1)
			{
				clName = splitCl[splitCl.length - 1];
			}

			set(clName, cl);
		}
		return this;
	}

	/**
		Sets a class to this tea from a string.
		`cl` will be formatted, for example: `sys.io.File` -> `File`.
		@param cl The class to set.
		@return this instance for chaining.
	**/
	public function setClassString(cl:String):SScript
	{
		if (_destroyed)
			return null;

		if (cl == null || cl.length < 1)
		{
			if (traces)
				trace('Class cannot be null');

			return null;
		}

		var cls:Class<Dynamic> = Type.resolveClass(cl);
		if (cls != null)
		{
			if (cl.split('.').length > 1)
			{
				cl = cl.split('.')[cl.split('.').length - 1];
			}

			set(cl, cls);
		}
		return this;
	}

	/**
		A special object is the object that'll get checked if a variable is not found in a Tea instance.
		
		Special object can't be basic types like Int, String, Float, Array and Bool.

		Instead, use it if you have a state instance.
		@param obj The special object. 
		@param includeFunctions If false, functions will be ignored in the special object. 
		@param exclusions Optional array of fields you want it to be excluded.
		@return Returns this instance for chaining.
	**/
	public function setSpecialObject(obj:Dynamic, ?includeFunctions:Bool = true, ?exclusions:Array<String>):SScript
	{
		if (_destroyed)
			return null;
		if (interp == null)
			return null;
		if (!active)
			return this;
		if (obj == null)
			return this;
		if (exclusions == null)
			exclusions = new Array();

		var types:Array<Dynamic> = [Int, String, Float, Bool, Array];
		for (i in types)
			if (Std.isOfType(obj, i))
				throw 'Special object cannot be ${i}';

		if (interp.specialObject == null)
			interp.specialObject = {obj: null, includeFunctions: null, exclusions: null};

		interp.specialObject.obj = obj;
		interp.specialObject.exclusions = exclusions.copy();
		interp.specialObject.includeFunctions = includeFunctions;
		return this;
	}
	
	/**
		Returns the local variables in this tea as a fresh map.

		Changing any value in returned map will not change the tea's variables.
	**/
	public function locals():Map<String, Dynamic>
	{
		if (_destroyed)
			return null;

		if (!active)
			return [];

		var newMap:Map<String, Dynamic> = new Map();
		for (i in interp.locals.keys())
		{
			var v = interp.locals[i];
			if (v != null)
				newMap[i] = v.r;
		}
		return newMap;
	}

	/**
		Removes a variable from this tea. 

		If a variable named `key` doesn't exist, unsetting won't do anything.
		@param key Variable name to remove.
		@return Returns this instance for chaining.
	**/
	public function unset(key:String):SScript
	{
		if (_destroyed)
			return null;

		if (interp == null || !active || key == null || (!interp.variables.exists(key) && !interp.finalVariables.exists(key)))
				return null;

		if (interp.variables.exists(key))
			interp.variables.remove(key);
		else 
			interp.finalVariables.remove(key);

		return this;
	}

	/**
		Gets a variable by name. 

		If a variable named as `key` does not exists return is null.
		@param key Variable name.
		@return The object got by name.
	**/
	public function get(key:String):Dynamic
	{
		if (_destroyed)
			return null;

		if (interp == null || !active)
		{
			if (traces)
			{
				if (interp == null)
					trace("This tea is unusable!");
				else
					trace("This tea is not active!");
			}

			return null;
		}

		var l = locals();
		if (l.exists(key))
			return l[key];

		return if (exists(key)) 
		{
			if (interp.variables.exists(key)) 
				interp.variables[key];
			else 
				interp.finalVariables[key];
		} else null;
	}

	/**
		Calls a function from this tea.

		`WARNING:` You MUST execute the tea once to get the functions into this tea.
		If you do not execute this tea and `call` a function, your call will be ignored.

		@param func Function name in tea. 
		@param args Arguments for the `func`. If the function does not require arguments, leave it null.
		@return Returns a sugar filled with called function, returned value etc. Returned value is at `returnValue`.
	**/
	public function call(func:String, ?args:Array<Dynamic>):Tea
	{
		if (_destroyed)
			return {
				exceptions: [new TeaException(new Exception((if (scriptFile != null && scriptFile.length > 0) scriptFile else "Tea instance") + " is destroyed."))],
				calledFunction: func,
				succeeded: false,
				returnValue: null,
				lastReportedTime: -1
			};

		if (!active)
			return {
				exceptions: [new TeaException(new Exception((if (scriptFile != null && scriptFile.length > 0) scriptFile else "Tea instance") + " is not active."))],
				calledFunction: func,
				succeeded: false,
				returnValue: null,
				lastReportedTime: -1
			};

		var time:Float = Timer.stamp();

		var scriptFile:String = if (scriptFile != null && scriptFile.length > 0) scriptFile else "";
		var caller:Tea = {
			exceptions: [],
			calledFunction: func,
			succeeded: false,
			returnValue: null,
			lastReportedTime: -1
		}
		#if sys
		if (scriptFile != null && scriptFile.length > 0)
			Reflect.setField(caller, "fileName", scriptFile);
		#end
		if (args == null)
			args = new Array();

		var pushedExceptions:Array<String> = new Array();
		function pushException(e:String)
		{
			if (!pushedExceptions.contains(e))
				caller.exceptions.push(new TeaException(new Exception(e)));
			
			pushedExceptions.push(e);
		}
		if (func == null)
		{
			if (traces)
				trace('Function name cannot be null for $scriptFile!');

			pushException('Function name cannot be null for $scriptFile!');
			return caller;
		}
		
		var fun = get(func);
		if (exists(func) && Type.typeof(fun) != TFunction)
		{
			if (traces)
				trace('$func is not a function');

			pushException('$func is not a function');
		}
		else if (interp == null || !exists(func))
		{
			if (interp == null)
			{
				if (traces)
					trace('Interpreter is null!');

				pushException('Interpreter is null!');
			}
			else
			{
				if (traces)
					trace('Function $func does not exist in $scriptFile.');

				if (scriptFile != null && scriptFile.length > 0)
					pushException('Function $func does not exist in $scriptFile.');
				else 
					pushException('Function $func does not exist in Tea instance.');
			}
		}
		else 
		{
			var oldCaller = caller;
			try
			{
				var functionField:Dynamic = Reflect.callMethod(this, fun, args);
				caller = {
					exceptions: caller.exceptions,
					calledFunction: func,
					succeeded: true,
					returnValue: functionField,
					lastReportedTime: -1,
				};
				#if sys
				if (scriptFile != null && scriptFile.length > 0)
					Reflect.setField(caller, "fileName", scriptFile);
				#end
				Reflect.setField(caller, "lastReportedTime", Timer.stamp() - time);
			}
			catch (e)
			{
				caller = oldCaller;
				caller.exceptions.insert(0, new TeaException(e));
			}
		}

		return caller;
	}

	/**
		Clears all of the keys assigned to this tea.

		@return Returns this instance for chaining.
	**/
	public function clear():SScript
	{
		if (_destroyed)
			return null;
		if (!active)
			return this;

		if (interp == null)
			return this;

		for (i in interp.variables.keys())
				interp.variables.remove(i);

		for (i in interp.finalVariables.keys())
			interp.finalVariables.remove(i);

		return this;
	}

	/**
		Tells if the `key` exists in this tea's interpreter.
		@param key The string to look for.
		@return Returns true if `key` is found in interpreter.
	**/
	public function exists(key:String):Bool
	{
		if (_destroyed)
			return false;
		if (!active)
			return false;

		if (interp == null)
			return false;
		var l = locals();
		if (l.exists(key))
			return l.exists(key);

		return interp.variables.exists(key) || interp.finalVariables.exists(key);
	}

	/**
		Sets some useful variables to interp to make easier using this tea.
		Override this function to set your custom sets aswell.
	**/
	public function preset():Void
	{
		if (_destroyed)
			return;
		if (!active)
			return;

		setClass(Date);
		setClass(DateTools);
		setClass(Math);
		setClass(Reflect);
		setClass(Std);
		setClass(SScript);
		setClass(StringTools);
		setClass(Type);

		#if sys
		setClass(File);
		setClass(FileSystem);
		setClass(Sys);
		#end
	}

	function resetInterp():Void
	{
		if (_destroyed)
			return;
		if (interp == null)
			return;

		interp.locals = #if haxe3 new Map() #else new Hash() #end;
		while (interp.declared.length > 0)
			interp.declared.pop();
		while (interp.pushedVars.length > 0)
			interp.pushedVars.pop();
	}

	function destroyInterp():Void 
	{
		if (_destroyed)
			return;
		if (interp == null)
			return;

		interp.locals = null;
		interp.variables = null;
		interp.finalVariables = null;
		interp.declared = null;
	}

	function doFile(scriptPath:String):Void
	{
		parsingException = null;

		if (_destroyed)
			return;

		if (scriptPath == null || scriptPath.length < 1 || BlankReg.match(scriptPath))
		{
			if (customOrigin != null)
				global[customOrigin] = this;
			else 
			{
				ID = IDCount + 1;
				IDCount++;
				global[Std.string(ID)] = this;
			}
			return;
		}

		if (scriptPath != null && scriptPath.length > 0)
		{
			#if sys
				if (FileSystem.exists(scriptPath))
				{
					scriptFile = scriptPath;
					script = File.getContent(scriptPath);
				}
				else
				{
					scriptFile = "";
					script = scriptPath;
				}
			#else
				scriptFile = "";
				script = scriptPath;
			#end

			if (scriptFile != null && scriptFile.length > 0)
				global[scriptFile] = this;
			else if (script != null && script.length > 0)
				global[script] = this;
		}
	}

	/**
		Executes a string once instead of a script file.

		This does not change your `scriptFile` but it changes `script`.

		Even though this function is faster,
		it should be avoided whenever possible.
		Always try to use a script file.
		@param string String you want to execute. If this argument is a file, this will act like `new` and will change `scriptFile`.
		@param origin Optional origin to use for this tea, it will appear on traces.
		@return Returns this instance for chaining. Will return `null` if failed.
	**/
	public function doString(string:String, ?origin:String):SScript
	{
		if (_destroyed)
			return null;
		if (!active)
			return null;
		if (string == null || string.length < 1 || BlankReg.match(string))
			return this;

		parsingException = null;

		var time = Timer.stamp();
		try 
		{
			#if sys
			if (FileSystem.exists(string))
			{
				scriptFile = string;
				origin = string;
				string = File.getContent(string);
			}
			#end

			var og:String = origin;
			if (og != null && og.length > 0)
				customOrigin = og;
			if (og == null || og.length < 1)
				og = customOrigin;
			if (og == null || og.length < 1)
				og = "SScript";

			if (!active || interp == null)
				return null;

			resetInterp();

			try
			{	
				script = string;

				if (customOrigin != null && customOrigin.length > 0)
				{
					if (ID != null)
						global.remove(Std.string(ID));
					global[customOrigin] = this;
				}
				else if (scriptFile != null && scriptFile.length > 0)
				{
					if (ID != null)
						global.remove(Std.string(ID));
					global[scriptFile] = this;
				}
				else if (script != null && script.length > 0)
				{
					if (ID != null)
						global.remove(Std.string(ID));
					global[script] = this;
				}

				var expr:Expr = parser.parseString(script, og);
				var r = interp.execute(expr);
				returnValue = r;
			}
			catch (e)
			{
				script = "";
				parsingException = e;
				returnValue = null;
			}
			
			lastReportedTime = Timer.stamp() - time;
 
			if (debugTraces)
			{
				if (lastReportedTime == 0)
					trace('Tea instance brewed instantly (0s)');
				else 
					trace('Tea instance brewed in ${lastReportedTime}s');
			}
		}
		catch (e) lastReportedTime = -1;

		return this;
	}

	inline function toString():String
	{
		if (_destroyed)
			return "null";

		if (scriptFile != null && scriptFile.length > 0)
			return scriptFile;

		return "[Tea Tea]";
	}

	#if (sys)
	/**
		Checks for teas in the provided path and returns them as an array.

		Make sure `path` is a directory!

		If `extensions` is not `null`, files' extensions will be checked.
		Otherwise, only files with the `.hx` extensions will be checked and listed.

		@param path The directory to check for. Nondirectory paths will be ignored.
		@param extensions Optional extension to check in file names.
		@return The teas in an array.
	**/
	#else
	/**
		Checks for teas in the provided path and returns them as an array.

		This function will always return an empty array, because you are targeting an unsupported target.
		@return An empty array.
	**/
	#end
	public static function listScripts(path:String, ?extensions:Array<String>):Array<SScript>
	{
		if (!path.endsWith('/'))
			path += '/';

		if (extensions == null || extensions.length < 1)
			extensions = ['hx'];

		var list:Array<SScript> = [];
		#if sys
		if (FileSystem.exists(path) && FileSystem.isDirectory(path))
		{
			var files:Array<String> = FileSystem.readDirectory(path);
			for (i in files)
			{
				var hasExtension:Bool = false;
				for (l in extensions)
				{
					if (i.endsWith(l))
					{
						hasExtension = true;
						break;
					}
				}
				if (hasExtension && FileSystem.exists(path + i))
					list.push(new SScript(path + i));
			}
		}
		#end
		
		return list;
	}

	/**
		This function makes this tea **COMPLETELY** unusable and unrestorable.

		If you don't want to destroy your tea just yet, just set `active` to false!
	**/
	public function destroy():Void
	{
		if (_destroyed)
			return;

		if (global.exists(scriptFile) && scriptFile != null && scriptFile.length > 0)
			global.remove(scriptFile);
		else if (global.exists(script) && script != null && script.length > 0)
			global.remove(script);
		if (global.exists(customOrigin))
			global.remove(customOrigin);
		if (global.exists(Std.string(ID)))
			global.remove(script);
		
		if (classPath != null && classPath.length > 0)
		{
			Interp.classes.remove(classPath);
			Interp.STATICPACKAGES[classPath] = null;
			Interp.STATICPACKAGES.remove(classPath);
		}

		for (i in interp.pushedClasses)
		{
			Interp.classes.remove(i);
			Interp.STATICPACKAGES[i] = null;
			Interp.STATICPACKAGES.remove(i);
		} 

		for (i in interp.pushedAbs)
		{
			Interp.eabstracts.remove(i);
			Interp.EABSTRACTS[i].tea = null;
			Interp.EABSTRACTS[i].fileName = null;
			Interp.EABSTRACTS.remove(i);
		} 
		
		for (i in interp.pushedVars) 
		{
			if (strictGlobalVariables.exists(i))
				strictGlobalVariables.remove(i);
		}

		clear();
		resetInterp();
		destroyInterp();

		customOrigin = null;
		parser = null;
		interp = null;
		script = null;
		scriptFile = null;
		active = false;
		notAllowedClasses = null;
		lastReportedTime = -1;
		ID = null;
		parsingException = null;
		returnValue = null;
		_destroyed = true;
	}

	function get_variables():Map<String, Dynamic>
	{
		if (_destroyed)
			return null;

		return interp.variables;
	}

	function get_classPath():String 
	{
		if (_destroyed)
			return null;

		return classPath;
	}

	function setClassPath(p):String 
	{
		if (_destroyed)
			return null;

		return classPath = p;
	}

	function setPackagePath(p):String
	{
		if (_destroyed)
			return null;

		return packagePath = p;
	}

	function get_packagePath():String
	{
		if (_destroyed)
			return null;

		return packagePath;
	}

	static function get_BlankReg():EReg 
	{
		return ~/^[\n\r\t]$/;
	}

	function set_customOrigin(value:String):String
	{
		if (_destroyed)
			return null;
		if (global.exists(value))
			throw "Origin " + value + " already exists in global.";
		
		@:privateAccess parser.origin = value;
		return customOrigin = value;
	}

	static function set_defaultTypeCheck(value:Null<Bool>):Null<Bool> 
	{
		for (i in global)
		{
			i.typeCheck = value == null ? false : value;
			//i.execute();
		}

		return defaultTypeCheck = value;
	}

	static function set_defaultDebug(value:Null<Bool>):Null<Bool> 
	{
		for (i in global)
		{
			i.debugTraces = value == null ? false : value;
			//i.execute();
		}
	
		return defaultDebug = value;
	}

	function get_parsingExceptions():Array<Exception> 
	{
		if (_destroyed)
			return null;

		if (parsingException == null)
			return [];

		return @:privateAccess [parsingException.toException()];
	}
}