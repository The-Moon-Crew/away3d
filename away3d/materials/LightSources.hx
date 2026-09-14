package away3d.materials;

enum abstract LightSources(Int) from Int to Int
{
	var LIGHTS = 0x01;
	var PROBES = 0x02;
	var ALL    = 0x03;

	public inline function contains(flag:LightSources):Bool
	{
		return (this & flag) == flag;
	}

	public inline function add(flag:LightSources):LightSources
	{
		return this | flag;
	}

	public inline function remove(flag:LightSources):LightSources
	{
		return this & ~flag;
	}

	@:op(A | B) 
	public static inline function combine(a:LightSources, b:LightSources):LightSources
	{
		return a | b;
	}

	@:op(A & B) 
	public static inline function intersect(a:LightSources, b:LightSources):LightSources
	{
		return a & b;
	}
}
