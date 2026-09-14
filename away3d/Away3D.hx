package away3d;

enum abstract BuildStage(String) to String
{
	var ALPHA = "alpha";
	var BETA = "beta";
	var RC = "rc";
	var RELEASE = "stable";
}

@:final
class Away3D
{
	public static final WEBSITE_URL:String = "https://away3d.com";
	public static final REPOSITORY_URL:String = "https://github.com/openfl/away3d";
	
	public static final MAJOR_VERSION:Int = 5;
	public static final MINOR_VERSION:Int = 0;
	public static final REVISION:Int = 0;
	public static final STAGE:BuildStage = BuildStage.RELEASE;

	public static var version(get, never):String;

	public static inline function isAtLeast(major:Int, minor:Int = 0, revision:Int = 0):Bool
	{
		if (MAJOR_VERSION != major) return MAJOR_VERSION > major;
		if (MINOR_VERSION != minor) return MINOR_VERSION > minor;
		return REVISION >= revision;
	}

	private static inline function get_version():String
	{
		var base = '$MAJOR_VERSION.$MINOR_VERSION.$REVISION';
		return STAGE == BuildStage.RELEASE ? base : '$base-$STAGE';
	}
}
