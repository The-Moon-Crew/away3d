package away3d.animators;

import away3d.animators.nodes.AnimationNodeBase;
import away3d.animators.states.IAnimationState;
import away3d.entities.Mesh;
import away3d.events.AnimatorEvent;
import away3d.library.assets.Asset3DType;
import away3d.library.assets.IAsset;
import away3d.library.assets.NamedAssetBase;
import openfl.events.Event;
import openfl.events.EventDispatcher;
import openfl.geom.Vector3D;
import openfl.Lib;

@:allow(away3d)
class AnimatorBase extends NamedAssetBase implements IAsset
{
	private static var _ticker:EventDispatcher = new EventDispatcher();

	public var absoluteTime(get, never):Int;
	public var animationSet(get, never):IAnimationSet;
	public var activeState(get, never):IAnimationState;
	public var activeAnimation(get, never):AnimationNodeBase;
	public var activeAnimationName(get, never):String;
	public var autoUpdate(get, set):Bool;
	public var time(get, set):Int;
	public var playbackSpeed(get, set):Float;
	public var assetType(get, never):String;
	public var isPlaying(get, never):Bool;
	public var isPaused(get, never):Bool;

	public var updatePosition:Bool = true;

	private var _isPlaying:Bool = false;
	private var _isPaused:Bool = false;
	private var _autoUpdate:Bool = true;
	private var _time:Int = 0;
	private var _playbackSpeed:Float = 1.0;
	private var _absoluteTime:Int = 0;

	private var _animationSet:IAnimationSet;
	private var _owners:Array<Mesh> = [];
	private var _activeNode:AnimationNodeBase;
	private var _activeState:IAnimationState;
	private var _activeAnimationName:String;
	private var _animationStates:Map<AnimationNodeBase, IAnimationState> = new Map();

	private var _startEvent:AnimatorEvent;
	private var _stopEvent:AnimatorEvent;
	private var _cycleEvent:AnimatorEvent;

	public function new(animationSet:IAnimationSet)
	{
		super();
		_animationSet = animationSet;
	}

	public function play(name:String, stateTransition:Float = 0.2, offset:Int = 0):IAnimationState
	{
		if (_activeAnimationName == name && _isPlaying && !_isPaused)
			return _activeState;

		var node = _animationSet.getAnimation(name);
		if (node == null)
			throw 'Animation "$name" not found in AnimationSet.';

		_activeAnimationName = name;
		_activeNode = node;
		_activeState = getAnimationState(node);

		if (offset != 0)
			_activeState.offset(offset + _absoluteTime);

		_isPaused = false;

		if (!_isPlaying && _autoUpdate)
			start();

		return _activeState;
	}

	public function pause():Void
	{
		if (!_isPlaying || _isPaused)
			return;

		_isPaused = true;
		_ticker.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
	}

	public function resume():Void
	{
		if (!_isPlaying || !_isPaused)
			return;

		_isPaused = false;
		_time = Lib.getTimer();
		_ticker.addEventListener(Event.ENTER_FRAME, onEnterFrame);
	}

	public function getAnimationState(node:AnimationNodeBase):IAnimationState
	{
		if (node == null) return null;

		var state = _animationStates.get(node);
		if (state == null)
		{
			state = node.stateConstructor(cast this, node);
			_animationStates.set(node, state);
		}
		return state;
	}

	public function getAnimationStateByName(name:String):IAnimationState
	{
		var node = _animationSet.getAnimation(name);
		return node != null ? getAnimationState(node) : null;
	}

	public function phase(value:Float):Void
	{
		if (_activeState != null)
			_activeState.phase(value);
	}

	public function start():Void
	{
		if (_isPlaying || !_autoUpdate)
			return;

		_time = _absoluteTime = Lib.getTimer();
		_isPlaying = true;
		_isPaused = false;

		_ticker.addEventListener(Event.ENTER_FRAME, onEnterFrame);

		if (hasEventListener(AnimatorEvent.START))
		{
			if (_startEvent == null)
				_startEvent = new AnimatorEvent(AnimatorEvent.START, this);
			dispatchEvent(_startEvent);
		}
	}

	public function stop():Void
	{
		if (!_isPlaying)
			return;

		_isPlaying = false;
		_isPaused = false;
		_ticker.removeEventListener(Event.ENTER_FRAME, onEnterFrame);

		if (hasEventListener(AnimatorEvent.STOP))
		{
			if (_stopEvent == null)
				_stopEvent = new AnimatorEvent(AnimatorEvent.STOP, this);
			dispatchEvent(_stopEvent);
		}
	}

	public function update(time:Int):Void
	{
		if (_isPaused)
			return;

		var delta = Std.int((time - _time) * _playbackSpeed);
		updateDeltaTime(delta);
		_time = time;
	}

	public function reset(name:String, offset:Int = 0):Void
	{
		var state = getAnimationStateByName(name);
		if (state != null)
			state.offset(offset + _absoluteTime);
	}

	private function addOwner(mesh:Mesh):Void
	{
		if (_owners.indexOf(mesh) == -1)
			_owners.push(mesh);
	}

	private function removeOwner(mesh:Mesh):Void
	{
		_owners.remove(mesh);
	}

	private function updateDeltaTime(dt:Int):Void
	{
		_absoluteTime += dt;

		if (_activeState != null)
		{
			_activeState.update(_absoluteTime);
			if (updatePosition)
				applyPositionDelta();
		}
	}

	private function onEnterFrame(event:Event = null):Void
	{
		update(Lib.getTimer());
	}

	private function applyPositionDelta():Void
	{
		var delta:Vector3D = _activeState.positionDelta;
		var dist:Float = delta.length;
		if (dist > 0)
		{
			for (owner in _owners)
				owner.translateLocal(delta, dist);
		}
	}

	private function dispatchCycleEvent():Void
	{
		if (hasEventListener(AnimatorEvent.CYCLE_COMPLETE))
		{
			if (_cycleEvent == null)
				_cycleEvent = new AnimatorEvent(AnimatorEvent.CYCLE_COMPLETE, this);
			dispatchEvent(_cycleEvent);
		}
	}

	public function dispose():Void
	{
		stop();

		for (state in _animationStates)
		{
			if (state != null)
				state.dispose();
		}

		_owners = [];
		_animationStates = new Map();
		_activeNode = null;
		_activeState = null;
		_animationSet = null;
	}

	private inline function get_absoluteTime():Int return _absoluteTime;
	private inline function get_animationSet():IAnimationSet return _animationSet;
	private inline function get_activeState():IAnimationState return _activeState;
	private inline function get_activeAnimation():AnimationNodeBase return _activeNode;
	private inline function get_activeAnimationName():String return _activeAnimationName;
	private inline function get_isPlaying():Bool return _isPlaying;
	private inline function get_isPaused():Bool return _isPaused;
	private inline function get_autoUpdate():Bool return _autoUpdate;

	private function set_autoUpdate(value:Bool):Bool
	{
		if (_autoUpdate == value)
			return value;

		_autoUpdate = value;
		if (_autoUpdate)
			start();
		else
			stop();

		return value;
	}

	private inline function get_time():Int return _time;

	private function set_time(value:Int):Int
	{
		if (_time == value)
			return value;

		update(value);
		return value;
	}

	private inline function get_playbackSpeed():Float return _playbackSpeed;
	private inline function set_playbackSpeed(value:Float):Float return _playbackSpeed = value;
	private inline function get_assetType():String return Asset3DType.ANIMATOR;
}
