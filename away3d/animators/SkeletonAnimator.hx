package away3d.animators;

import away3d.animators.data.JointPose;
import away3d.animators.data.Quaternion;
import away3d.animators.data.Skeleton;
import away3d.animators.data.SkeletonAnimationSet;
import away3d.animators.data.SkeletonJoint;
import away3d.animators.data.SkeletonPose;
import away3d.animators.nodes.AnimationNodeBase;
import away3d.animators.states.ISkeletonAnimationState;
import away3d.animators.transitions.IAnimationTransition;
import away3d.cameras.Camera3D;
import away3d.core.base.IRenderable;
import away3d.core.base.SkinnedSubGeometry;
import away3d.core.base.SubMesh;
import away3d.core.managers.Stage3DProxy;
import away3d.events.AnimationStateEvent;
import away3d.materials.passes.MaterialPassBase;
import openfl.display3D.Context3DProgramType;
import openfl.geom.Vector3D;
import openfl.Vector;

@:allow(away3d)
class SkeletonAnimator extends AnimatorBase implements IAnimator
{
	public var globalMatrices(get, never):Vector<Float>;
	public var globalPose(get, never):SkeletonPose;
	public var skeleton(get, never):Skeleton;
	public var forceCPU(get, never):Bool;
	public var useCondensedIndices(get, set):Bool;
	public var blendWeight(get, set):Float;

	private var _globalMatrices:Vector<Float>;
	private var _globalPose:SkeletonPose = new SkeletonPose();
	private var _globalPropertiesDirty:Bool = true;
	private var _numJoints:Int = 0;
	private var _skeletonAnimationStates:Map<SkinnedSubGeometry, SubGeomAnimationState> = new Map();
	private var _condensedMatrices:Vector<Float> = new Vector<Float>();

	private var _skeleton:Skeleton;
	private var _forceCPU:Bool;
	private var _useCondensedIndices:Bool = false;
	private var _jointsPerVertex:Int;
	private var _activeSkeletonState:ISkeletonAnimationState;

	private var _blendWeight:Float = 1.0;
	private var _secondaryState:ISkeletonAnimationState;
	private var _secondaryNode:AnimationNodeBase;

	public function new(animationSet:SkeletonAnimationSet, skeleton:Skeleton, forceCPU:Bool = false)
	{
		super(animationSet);

		_skeleton = skeleton;
		_forceCPU = forceCPU;
		_jointsPerVertex = animationSet.jointsPerVertex;
		_numJoints = _skeleton.numJoints;

		_globalMatrices = new Vector<Float>(_numJoints * 12, true);
		initMatrices();
	}

	private inline function initMatrices():Void
	{
		var idx:Int = 0;
		for (i in 0..._numJoints)
		{
			_globalMatrices[idx++] = 1.0; _globalMatrices[idx++] = 0.0; _globalMatrices[idx++] = 0.0; _globalMatrices[idx++] = 0.0;
			_globalMatrices[idx++] = 0.0; _globalMatrices[idx++] = 1.0; _globalMatrices[idx++] = 0.0; _globalMatrices[idx++] = 0.0;
			_globalMatrices[idx++] = 0.0; _globalMatrices[idx++] = 0.0; _globalMatrices[idx++] = 1.0; _globalMatrices[idx++] = 0.0;
		}
	}

	public override function play(name:String, ?stateTransition:Dynamic = null, offset:Int = 0):ISkeletonAnimationState
	{
		if (Std.isOfType(stateTransition, IAnimationTransition))
		{
			var transition:IAnimationTransition = cast stateTransition;
			if (_activeAnimationName != name)
			{
				_activeAnimationName = name;
				var targetNode = _animationSet.getAnimation(name);
				if (targetNode == null)
					throw 'Animation "$name" not found in AnimationSet.';

				if (_activeNode != null)
				{
					_activeNode = transition.getAnimationNode(this, _activeNode, targetNode, _absoluteTime);
					_activeNode.addEventListener(AnimationStateEvent.TRANSITION_COMPLETE, onTransitionComplete);
				}
				else
				{
					_activeNode = targetNode;
				}

				_activeState = getAnimationState(_activeNode);
				_activeSkeletonState = cast(_activeState, ISkeletonAnimationState);

				if (updatePosition)
				{
					_activeState.update(_absoluteTime);
					_activeState.positionDelta;
				}
			}
		}
		else
		{
			var transTime:Float = (stateTransition != null && Std.isOfType(stateTransition, Float)) ? cast stateTransition : 0.2;
			super.play(name, transTime, offset);
			_activeSkeletonState = cast(_activeState, ISkeletonAnimationState);
		}

		if (offset != 0)
			reset(name, offset);

		return _activeSkeletonState;
	}

	public function blend(primaryName:String, secondaryName:String, weight:Float):Void
	{
		_activeNode = _animationSet.getAnimation(primaryName);
		_secondaryNode = _animationSet.getAnimation(secondaryName);

		if (_activeNode == null || _secondaryNode == null)
			throw 'One or both animation nodes ("$primaryName", "$secondaryName") were not found.';

		_activeAnimationName = primaryName;
		_activeState = getAnimationState(_activeNode);
		_activeSkeletonState = cast(_activeState, ISkeletonAnimationState);

		_secondaryState = cast(getAnimationState(_secondaryNode), ISkeletonAnimationState);
		_blendWeight = Math.max(0.0, Math.min(1.0, weight));

		if (!_isPlaying && _autoUpdate)
			start();
	}

	public function clone():IAnimator
	{
		return new SkeletonAnimator(cast(_animationSet, SkeletonAnimationSet), _skeleton, _forceCPU);
	}

	public function setRenderState(stage3DProxy:Stage3DProxy, renderable:IRenderable, vertexConstantOffset:Int, vertexStreamOffset:Int, camera:Camera3D):Void
	{
		if (_globalPropertiesDirty)
			updateGlobalProperties();

		var subMesh:SubMesh = cast renderable;
		var skinnedGeom:SkinnedSubGeometry = cast subMesh.subGeometry;

		if (_useCondensedIndices)
		{
			var numCondensedJoints:Int = skinnedGeom.numCondensedJoints;
			if (numCondensedJoints == 0)
			{
				skinnedGeom.condenseIndexData();
				numCondensedJoints = skinnedGeom.numCondensedJoints;
			}
			updateCondensedMatrices(skinnedGeom.condensedIndexLookUp, numCondensedJoints);
			stage3DProxy.context3D.setProgramConstantsFromVector(Context3DProgramType.VERTEX, vertexConstantOffset, _condensedMatrices, numCondensedJoints * 3);
		}
		else
		{
			if (_animationSet.usesCPU)
			{
				var subGeomAnimState = _skeletonAnimationStates.get(skinnedGeom);
				if (subGeomAnimState == null)
				{
					subGeomAnimState = new SubGeomAnimationState(skinnedGeom);
					_skeletonAnimationStates.set(skinnedGeom, subGeomAnimState);
				}

				if (subGeomAnimState.dirty)
				{
					morphGeometry(subGeomAnimState, skinnedGeom);
					subGeomAnimState.dirty = false;
				}
				skinnedGeom.updateAnimatedData(subGeomAnimState.animatedVertexData);
				return;
			}
			stage3DProxy.context3D.setProgramConstantsFromVector(Context3DProgramType.VERTEX, vertexConstantOffset, _globalMatrices, _numJoints * 3);
		}

		skinnedGeom.activateJointIndexBuffer(vertexStreamOffset, stage3DProxy);
		skinnedGeom.activateJointWeightsBuffer(vertexStreamOffset + 1, stage3DProxy);
	}

	public function testGPUCompatibility(pass:MaterialPassBase):Void
	{
		if (!_useCondensedIndices && (_forceCPU || _jointsPerVertex > 4 || pass.numUsedVertexConstants + _numJoints * 3 > 128))
			_animationSet.cancelGPUCompatibility();
	}

	private override function updateDeltaTime(dt:Int):Void
	{
		super.updateDeltaTime(dt);

		if (_secondaryState != null)
			_secondaryState.update(_absoluteTime);

		_globalPropertiesDirty = true;

		for (state in _skeletonAnimationStates)
			state.dirty = true;
	}

	private function updateCondensedMatrices(condensedIndexLookUp:Vector<UInt>, numJoints:Int):Void
	{
		var j:Int = 0;
		_condensedMatrices.length = numJoints * 12;

		for (i in 0...numJoints)
		{
			var srcIndex:Int = condensedIndexLookUp[i * 3] * 4;
			var limit:Int = srcIndex + 12;
			while (srcIndex < limit)
				_condensedMatrices[j++] = _globalMatrices[srcIndex++];
		}
	}

	private function updateGlobalProperties():Void
	{
		_globalPropertiesDirty = false;
		if (_activeSkeletonState == null) return;

		var pose:SkeletonPose = _activeSkeletonState.getSkeletonPose(_skeleton);

		if (_secondaryState != null && _blendWeight < 1.0)
		{
			var secPose:SkeletonPose = _secondaryState.getSkeletonPose(_skeleton);
			pose = blendPoses(pose, secPose, _blendWeight);
		}

		localToGlobalPose(pose, _globalPose, _skeleton);

		var mtxOffset:Int = 0;
		var globalPoses:Vector<JointPose> = _globalPose.jointPoses;
		var joints:Vector<SkeletonJoint> = _skeleton.joints;

		for (i in 0..._numJoints)
		{
			var p:JointPose = globalPoses[i];
			var quat:Quaternion = p.orientation;
			var vec:Vector3D = p.translation;

			var ox:Float = quat.x, oy:Float = quat.y, oz:Float = quat.z, ow:Float = quat.w;
			var t:Float = 2.0 * ox;
			var xy2:Float = t * oy, xz2:Float = t * oz, xw2:Float = t * ow;
			t = 2.0 * oy;
			var yz2:Float = t * oz, yw2:Float = t * ow;
			var zw2:Float = 2.0 * oz * ow;

			var xx:Float = ox * ox, yy:Float = oy * oy, zz:Float = oz * oz, ww:Float = ow * ow;

			var n11:Float = xx - yy - zz + ww;
			var n12:Float = xy2 - zw2;
			var n13:Float = xz2 + yw2;
			var n21:Float = xy2 + zw2;
			var n22:Float = -xx + yy - zz + ww;
			var n23:Float = yz2 - xw2;
			var n31:Float = xz2 - yw2;
			var n32:Float = yz2 + xw2;
			var n33:Float = -xx - yy + zz + ww;

			var raw:Vector<Float> = joints[i].inverseBindPose;
			var m11:Float = raw[0],  m12:Float = raw[4],  m13:Float = raw[8],  m14:Float = raw[12];
			var m21:Float = raw[1],  m22:Float = raw[5],  m23:Float = raw[9],  m24:Float = raw[13];
			var m31:Float = raw[2],  m32:Float = raw[6],  m33:Float = raw[10], m34:Float = raw[14];

			_globalMatrices[mtxOffset]     = n11 * m11 + n12 * m21 + n13 * m31;
			_globalMatrices[mtxOffset + 1] = n11 * m12 + n12 * m22 + n13 * m32;
			_globalMatrices[mtxOffset + 2] = n11 * m13 + n12 * m23 + n13 * m33;
			_globalMatrices[mtxOffset + 3] = n11 * m14 + n12 * m24 + n13 * m34 + vec.x;

			_globalMatrices[mtxOffset + 4] = n21 * m11 + n22 * m21 + n23 * m31;
			_globalMatrices[mtxOffset + 5] = n21 * m12 + n22 * m22 + n23 * m32;
			_globalMatrices[mtxOffset + 6] = n21 * m13 + n22 * m23 + n23 * m33;
			_globalMatrices[mtxOffset + 7] = n21 * m14 + n22 * m24 + n23 * m34 + vec.y;

			_globalMatrices[mtxOffset + 8]  = n31 * m11 + n32 * m21 + n33 * m31;
			_globalMatrices[mtxOffset + 9]  = n31 * m12 + n32 * m22 + n33 * m32;
			_globalMatrices[mtxOffset + 10] = n31 * m13 + n32 * m23 + n33 * m33;
			_globalMatrices[mtxOffset + 11] = n31 * m14 + n32 * m24 + n33 * m34 + vec.z;

			mtxOffset += 12;
		}
	}

	private function blendPoses(poseA:SkeletonPose, poseB:SkeletonPose, alpha:Float):SkeletonPose
	{
		var blended:SkeletonPose = new SkeletonPose();
		var len:Int = poseA.numJointPoses;
		blended.jointPoses.length = len;

		var invAlpha:Float = 1.0 - alpha;

		for (i in 0...len)
		{
			var jp:JointPose = new JointPose();
			var pA:JointPose = poseA.jointPoses[i];
			var pB:JointPose = poseB.jointPoses[i];

			jp.translation.x = pA.translation.x * alpha + pB.translation.x * invAlpha;
			jp.translation.y = pA.translation.y * alpha + pB.translation.y * invAlpha;
			jp.translation.z = pA.translation.z * alpha + pB.translation.z * invAlpha;

			jp.orientation.slerp(pB.orientation, pA.orientation, alpha);
			blended.jointPoses[i] = jp;
		}

		return blended;
	}

	private function morphGeometry(state:SubGeomAnimationState, subGeom:SkinnedSubGeometry):Void
	{
		var vertexData:Vector<Float> = subGeom.vertexData;
		var targetData:Vector<Float> = state.animatedVertexData;
		var jointIndices:Vector<Float> = subGeom.jointIndexData;
		var jointWeights:Vector<Float> = subGeom.jointWeightsData;

		var index:Int = 0;
		var j:Int = 0;
		var len:Int = vertexData.length;

		while (index < len)
		{
			var vertX:Float = vertexData[index],     vertY:Float = vertexData[index + 1], vertZ:Float = vertexData[index + 2];
			var normX:Float = vertexData[index + 3], normY:Float = vertexData[index + 4], normZ:Float = vertexData[index + 5];
			var tangX:Float = vertexData[index + 6], tangY:Float = vertexData[index + 7], tangZ:Float = vertexData[index + 8];

			var vx:Float = 0, vy:Float = 0, vz:Float = 0;
			var nx:Float = 0, ny:Float = 0, nz:Float = 0;
			var tx:Float = 0, ty:Float = 0, tz:Float = 0;

			var k:Int = 0;
			while (k < _jointsPerVertex)
			{
				var weight:Float = jointWeights[j];
				if (weight > 0)
				{
					var mtxOffset:Int = Std.int(jointIndices[j++]) << 2;
					var m11:Float = _globalMatrices[mtxOffset],     m12:Float = _globalMatrices[mtxOffset + 1], m13:Float = _globalMatrices[mtxOffset + 2], m14:Float = _globalMatrices[mtxOffset + 3];
					var m21:Float = _globalMatrices[mtxOffset + 4], m22:Float = _globalMatrices[mtxOffset + 5], m23:Float = _globalMatrices[mtxOffset + 6], m24:Float = _globalMatrices[mtxOffset + 7];
					var m31:Float = _globalMatrices[mtxOffset + 8], m32:Float = _globalMatrices[mtxOffset + 9], m33:Float = _globalMatrices[mtxOffset + 10], m34:Float = _globalMatrices[mtxOffset + 11];

					vx += weight * (m11 * vertX + m12 * vertY + m13 * vertZ + m14);
					vy += weight * (m21 * vertX + m22 * vertY + m23 * vertZ + m24);
					vz += weight * (m31 * vertX + m32 * vertY + m33 * vertZ + m34);

					nx += weight * (m11 * normX + m12 * normY + m13 * normZ);
					ny += weight * (m21 * normX + m22 * normY + m23 * normZ);
					nz += weight * (m31 * normX + m32 * normY + m33 * normZ);

					tx += weight * (m11 * tangX + m12 * tangY + m13 * tangZ);
					ty += weight * (m21 * tangX + m22 * tangY + m23 * tangZ);
					tz += weight * (m31 * tangX + m32 * tangY + m33 * tangZ);

					k++;
				}
				else
				{
					j += _jointsPerVertex - k;
					k = _jointsPerVertex;
				}
			}

			targetData[index]     = vx; targetData[index + 1] = vy; targetData[index + 2] = vz;
			targetData[index + 3] = nx; targetData[index + 4] = ny; targetData[index + 5] = nz;
			targetData[index + 6] = tx; targetData[index + 7] = ty; targetData[index + 8] = tz;

			index += 13;
		}
	}

	private function localToGlobalPose(sourcePose:SkeletonPose, targetPose:SkeletonPose, skeleton:Skeleton):Void
	{
		var globalPoses:Vector<JointPose> = targetPose.jointPoses;
		var joints:Vector<SkeletonJoint> = skeleton.joints;
		var len:Int = sourcePose.numJointPoses;
		var jointPoses:Vector<JointPose> = sourcePose.jointPoses;

		if (globalPoses.length != len)
			globalPoses.length = len;

		for (i in 0...len)
		{
			if (globalPoses[i] == null)
				globalPoses[i] = new JointPose();

			var globalJointPose:JointPose = globalPoses[i];
			var joint:SkeletonJoint = joints[i];
			var parentIndex:Int = joint.parentIndex;
			var pose:JointPose = jointPoses[i];

			var q:Quaternion = globalJointPose.orientation;
			var t:Vector3D = globalJointPose.translation;

			if (parentIndex < 0)
			{
				var tr:Vector3D = pose.translation;
				var or:Quaternion = pose.orientation;
				q.x = or.x; q.y = or.y; q.z = or.z; q.w = or.w;
				t.x = tr.x; t.y = tr.y; t.z = tr.z;
			}
			else
			{
				var parentPose:JointPose = globalPoses[parentIndex];
				if (parentPose == null)
				{
					parentPose = new JointPose();
					globalPoses[parentIndex] = parentPose;
				}

				var or:Quaternion = parentPose.orientation;
				var tr:Vector3D = pose.translation;

				var x2:Float = or.x, y2:Float = or.y, z2:Float = or.z, w2:Float = or.w;
				var x3:Float = tr.x, y3:Float = tr.y, z3:Float = tr.z;

				var w1:Float = -x2 * x3 - y2 * y3 - z2 * z3;
				var x1:Float =  w2 * x3 + y2 * z3 - z2 * y3;
				var y1:Float =  w2 * y3 - x2 * z3 + z2 * x3;
				var z1:Float =  w2 * z3 + x2 * y3 - y2 * x3;

				tr = parentPose.translation;
				t.x = -w1 * x2 + x1 * w2 - y1 * z2 + z1 * y2 + tr.x;
				t.y = -w1 * y2 + x1 * z2 + y1 * w2 - z1 * x2 + tr.y;
				t.z = -w1 * z2 - x1 * y2 + y1 * x2 + z1 * w2 + tr.z;

				x1 = or.x; y1 = or.y; z1 = or.z; w1 = or.w;
				or = pose.orientation;
				x2 = or.x; y2 = or.y; z2 = or.z; w2 = or.w;

				q.w = w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2;
				q.x = w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2;
				q.y = w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2;
				q.z = w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2;
			}
		}
	}

	private function onTransitionComplete(event:AnimationStateEvent):Void
	{
		event.animationNode.removeEventListener(AnimationStateEvent.TRANSITION_COMPLETE, onTransitionComplete);
		if (_activeState == event.animationState)
		{
			_activeNode = _animationSet.getAnimation(_activeAnimationName);
			_activeState = getAnimationState(_activeNode);
			_activeSkeletonState = cast(_activeState, ISkeletonAnimationState);
		}
	}

	public override function dispose():Void
	{
		super.dispose();
		_skeletonAnimationStates = new Map();
		_globalMatrices = null;
		_condensedMatrices = null;
		_skeleton = null;
		_activeSkeletonState = null;
		_secondaryState = null;
		_secondaryNode = null;
	}

	private inline function get_globalMatrices():Vector<Float>
	{
		if (_globalPropertiesDirty) updateGlobalProperties();
		return _globalMatrices;
	}

	private inline function get_globalPose():SkeletonPose
	{
		if (_globalPropertiesDirty) updateGlobalProperties();
		return _globalPose;
	}

	private inline function get_skeleton():Skeleton return _skeleton;
	private inline function get_forceCPU():Bool return _forceCPU;
	private inline function get_useCondensedIndices():Bool return _useCondensedIndices;
	private inline function set_useCondensedIndices(value:Bool):Bool return _useCondensedIndices = value;
	private inline function get_blendWeight():Float return _blendWeight;

	private function set_blendWeight(value:Float):Float
	{
		_blendWeight = Math.max(0.0, Math.min(1.0, value));
		_globalPropertiesDirty = true;
		return _blendWeight;
	}
}

class SubGeomAnimationState
{
	public var animatedVertexData:Vector<Float>;
	public var dirty:Bool = true;

	public function new(subGeom:SkinnedSubGeometry)
	{
		animatedVertexData = subGeom.vertexData.concat();
	}
}
