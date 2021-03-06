/* ***** BEGIN LICENSE BLOCK *****
 *
 * This file is part of Weave.
 *
 * The Initial Developer of Weave is the Institute for Visualization
 * and Perception Research at the University of Massachusetts Lowell.
 * Portions created by the Initial Developer are Copyright (C) 2008-2015
 * the Initial Developer. All Rights Reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 * 
 * ***** END LICENSE BLOCK ***** */

package weave.core
{
	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;
	import flash.display.Graphics;
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.events.TimerEvent;
	import flash.utils.Dictionary;
	import flash.utils.Timer;
	
	import mx.core.IUIComponent;
	import mx.core.IVisualElement;
	import mx.core.IVisualElementContainer;
	import mx.core.UIComponent;
	import mx.events.IndexChangedEvent;
	
	import weave.api.getCallbackCollection;
	import weave.api.objectWasDisposed;
	import weave.api.core.IChildListCallbackInterface;
	import weave.api.core.ILinkableDisplayObject;
	import weave.api.core.ILinkableHashMap;
	import weave.api.core.ILinkableObject;
	import weave.api.core.ILinkableVariable;
	import weave.api.ui.ILinkableLayoutManager;
	import weave.primitives.Dictionary2D;

	/**
	 * This is an all-static class containing functions related to UI and ILinkableObjects.
	 * 
	 * @author adufilie
	 * @author pkovac
	 */
	public class UIUtils
	{
		public static var debug:Boolean = false;
		
		/**
		 * Links a LinkableBoolean's session state to a component's <code>visible</code> and <code>includeInLayout</code> properties.
		 * @param relevantContext The context in which the linking remains relevant (usually <code>this</code>).
		 * @param shownState The LinkableBoolean.
		 * @param component The UIComponent.
		 * @param invert Set to true if shownState should be negated.
		 */
		public static function linkVisibility(relevantContext:Object, shownState:LinkableBoolean, component:Object, invert:Boolean = false):void
		{
			var target:UIComponent = UIComponent(component);
			shownState.addGroupedCallback(relevantContext, function():void {
				target.visible = target.includeInLayout = shownState.value != invert;
			}, true);
		}
		
		private static var recursiveHasFocus:Dictionary = new Dictionary(true);
		
		/**
		 * This function determines if a particular component or one of its children has input focus.
		 * Supports a "hasFocus" property on the component if present.
		 * @param component The component to test.
		 * @return true if the component has focus.
		 */
		public static function hasFocus(component:UIComponent):Boolean
		{
			if (!component)
				return false;
			var obj:DisplayObject = component.getFocus();
			if (obj && component.contains(obj))
				return true;
			
			if (!recursiveHasFocus[component] && component.hasOwnProperty('hasFocus'))
			{
				recursiveHasFocus[component] = true;
				var result:Boolean = component['hasFocus'];
				recursiveHasFocus[component] = false;
				if (result)
					return true;
			}
			
			return false;
		}
		
		/**
		 * This will set the following parameters of a component:
		 * paddingLeft, paddingRight, paddingTop, paddingBottom, percentWidth, percentHeight, minWidth, minHeight
		 * @param componentOrEvent A UIComponent or an event with a UIComponent target.
		 * @param padding Sets paddingLeft, paddingRight, paddingTop, and paddingBottom to the same value.
		 * @param percentWidth Sets percentWidth if not NaN
		 * @param percentHeight Sets percentHeight if not NaN
		 * @param collapsableToZero If true, sets minWidth,minHeight to zero
		 */
		public static function pad(componentOrEvent:Object, padding:int, percentWidth:Number = NaN, percentHeight:Number = NaN, collapsableToZero:Boolean = false):void
		{
			if (componentOrEvent is Event)
				componentOrEvent = (componentOrEvent as Event).target;
			
			var component:UIComponent = componentOrEvent as UIComponent;
			if (!component)
				throw new Error("First parameter must be either a UIComponent or an Event with a UIComponent currentTarget.");
			
			component.setStyle('paddingLeft', padding);
			component.setStyle('paddingTop', padding);
			component.setStyle('paddingRight', padding);
			component.setStyle('paddingBottom', padding);
			if (isFinite(percentWidth))
				component.percentWidth = percentWidth;
			if (isFinite(percentHeight))
				component.percentHeight = percentHeight;
			if (collapsableToZero)
				component.minWidth = component.minHeight = 0;
		}
		
		/**
		 * Draws an invisible border around the edge of a component for catching mouse events.
		 * @param sprite The component.
		 * @param haloDistance The halo's distance from the edge (may be negative for an inset halo)
		 */
		public static function drawInvisibleHalo(sprite:Sprite, haloDistance:Number):void
		{
			var d:Number = haloDistance;
			var w:Number = sprite.width;
			var h:Number = sprite.height;
			drawInvisiblePolygon(sprite, [
				0,0, w,0, w,h, 0,h, 0,0,
				0-d,0-d, w+d,0-d, w+d,h+d, 0-d,h+d, 0-d,0-d
			], false);
		}
		
		/**
		 * Draws an invisible polygon on a component for catching mouse events.
		 * @param sprite The component.
		 * @param coords An array containing coordinates like [x0,y0, x1,y1, ...].  If omitted, a default rectangle will be used.
		 * @param normalizedCoords true for normalized coordinates (x and y values will be multiplied by sprite.width and sprite.height)
		 * @param borderThickness The thickness of the polygon border in pixels.
		 */		
		public static function drawInvisiblePolygon(sprite:Sprite, coords:Array = null, normalizedCoords:Boolean = false, borderThickness:Number = 0):void
		{
			if (!coords)
				coords = [0,0, 1,0, 1,1, 0,1], normalizedCoords = true;
			
			if (coords.length < 4)
				return;
			
			var g:Graphics = sprite.graphics;
			g.moveTo(coords[0], coords[1]);
			g.beginFill(0xFF0000, debug ? 0.5 : 0);
			g.lineStyle(borderThickness, 0xFF0000, debug ? 0.5 : 0);
			var n:int = coords.length / 2;
			for (var i:int = 1; i <= n; i++)
			{
				var ix:int = i % n * 2;
				if (normalizedCoords)
					g.lineTo(sprite.width * coords[ix], sprite.height * coords[ix + 1]);
				else
					g.lineTo(coords[ix], coords[ix + 1]);
			}
			g.endFill();
		}
		
		/**
		 * @param component
		 * @param steps
		 * @param interval
		 * @author pkovac
		 */		
		public static function componentPulse(component:UIComponent, steps:Number = 15, interval:Number = 30):void
		{
			var anim:Timer = new Timer(interval, steps);
			/* TODO: Find out what class actually has the "focusAlpha" style */
			function clearPulseHandler(e:TimerEvent):void
			{
				if (!hasFocus(component))
					component.drawFocus(false); /* Don't turn off the focus style 
				if somehow it was acquired during the pulse */
				component.setStyle("focusAlpha", 0.4); /* reset focusAlpha to default */
			}
			function pulsingHandler(e:TimerEvent):void
			{
				var step:Number = (e.target as Timer).currentCount;
				if (step > (steps/2)) step = steps - step;
				component.setStyle("focusAlpha", step/(steps/2));
				component.drawFocus(true); /* is this really needed? */
			}
			anim.addEventListener(TimerEvent.TIMER, pulsingHandler);
			anim.addEventListener(TimerEvent.TIMER_COMPLETE, clearPulseHandler);
			anim.start();
			return;
		}
		
		/**
		 * This will add a callback to a linkable variable that will set a style property of a UIComponent.
		 * @param linkableVariable
		 * @param uiComponent
		 * @param stylePropertyName
		 */		
		public static function bindStyle(linkableVariable:ILinkableVariable, uiComponent:UIComponent, stylePropertyName:String, groupedCallback:Boolean = true):void
		{
			var callback:Function = function():void
			{
				if (!uiComponent.parent)
				{
					uiComponent.callLater(callback);
					return;
				}
				uiComponent.setStyle(stylePropertyName, linkableVariable.getSessionState());
			};
			
			if (groupedCallback)
				getCallbackCollection(linkableVariable).addGroupedCallback(null, callback, true);
			else
				getCallbackCollection(linkableVariable).addImmediateCallback(null, callback, true);
		}
		
		private static const linkFunctionCache:Dictionary2D = new Dictionary2D(true, true);
		
		/**
		 * This will set up a callback on a components hash map so they get added to an ILinkableLayoutManager. 
		 * @param layoutManager
		 * @param components
		 */
		public static function linkLayoutManager(layoutManager:ILinkableLayoutManager, components:ILinkableHashMap):void
		{
			// when the components list changes, we need to notify the layoutManager
			var clc:IChildListCallbackInterface = components.childListCallbacks;
			function componentListCallback():void
			{
				// add
				var newComponent:IVisualElement = clc.lastObjectAdded as IVisualElement;
				if (newComponent)
					layoutManager.addComponent(clc.lastNameAdded, newComponent);
				
				// remove
				var oldComponent:IVisualElement = clc.lastObjectRemoved as IVisualElement;
				if (oldComponent)
					layoutManager.removeComponent(clc.lastNameRemoved);
				
				// reorder
				if (!clc.lastObjectAdded && !clc.lastObjectRemoved)
					layoutManager.setComponentOrder(components.getNames());
			}
			components.childListCallbacks.addImmediateCallback(layoutManager, componentListCallback);
			
			// when layoutManager triggers callbacks, we need to synchronize the components list
			function layoutManagerCallback():void
			{
				getCallbackCollection(components).delayCallbacks();
				
				// for each component in the components list, if the layoutManager doesn't have that component, remove it from components list
				var names:Array = components.getNames(IUIComponent);
				for each (var name:String in names)
					if (!layoutManager.hasComponent(name))
						components.removeObject(name);
				// update order if necessary
				components.setNameOrder(layoutManager.getComponentOrder());
				
				getCallbackCollection(components).resumeCallbacks();
			}
			getCallbackCollection(layoutManager).addImmediateCallback(components, layoutManagerCallback);
			
			// add existing components
			var names:Array = components.getNames(IUIComponent);
			var objects:Array = components.getObjects(IUIComponent);
			
			getCallbackCollection(layoutManager).delayCallbacks();
			
			for (var i:int = 0; i < names.length; i++)
				layoutManager.addComponent(names[i] as String, objects[i] as IVisualElement);
			
			getCallbackCollection(layoutManager).resumeCallbacks();
		}
		
		/**
		 * This will set up a callback on a components hash map so they get added to an ILinkableLayoutManager. 
		 * @param layoutManager
		 * @param components
		 */
		public static function unlinkLayoutManager(layoutManager:ILinkableLayoutManager, components:ILinkableHashMap):void
		{
			//TODO
		}
		
		private static const _previousParents:Dictionary = new Dictionary(true);
		
		/**
		 * Returns the previous parent of a child if it was moved to a new parent using one of the static functions defined in this class.
		 */
		public static function getPreviousParent(child:DisplayObject):DisplayObjectContainer
		{
			return _previousParents[child];
		}
		
		/**
		 * This function adds a callback to a LinkableHashMap to monitor any DisplayObjects contained in it.
		 * @param uiParent A UIComponent to synchronize with the given hashMap.
		 * @param hashMap A LinkableHashMap containing DisplayObjects to synchronize with the given uiParent.
		 * @param keepLinkableChildrenOnTop If set to true, children of the hashMap will be kept on top of all other UI children.
		 */
		public static function linkDisplayObjects(uiParent:UIComponent, hashMap:ILinkableHashMap, keepLinkableChildrenOnTop:Boolean = false):void
		{
			if (linkFunctionCache.get(uiParent, hashMap) is Function) // already linked?
				unlinkDisplayObjects(uiParent, hashMap);
			
			var callback:Function = function():void { handleHashMapChildListChange(uiParent, hashMap, keepLinkableChildrenOnTop); };
			linkFunctionCache.set(uiParent, hashMap, callback);
			
			hashMap.childListCallbacks.addImmediateCallback(uiParent, callback);
			
			// add all existing sessioned DisplayObjects as children
			var names:Array = hashMap.getNames();
			for (var i:int = 0; i < names.length; i++)
				addChild(uiParent, hashMap, names[i], keepLinkableChildrenOnTop);
			
			// update hashMap name order when a child index changes
			var listener:Function = function (event:Event):void
			{
				if (parentToBusyFlagMap[uiParent])
					return;
				var newNameOrder:Array = [];
				var wrappers:Array = hashMap.getObjects(ILinkableDisplayObject);
				for (var i:int = 0; i < uiParent.numChildren; i++)
				{
					var name:String = null;
					// case 1: check if child is a registered linkable child of the hash map
					var child:DisplayObject = uiParent.getChildAt(i);
					if (child is ILinkableObject)
						name = hashMap.getName(child as ILinkableObject);
					if (name == null)
					{
						// case 2: check if child is the internal display object of an ILinkableDisplayObject
						for each (var wrapper:ILinkableDisplayObject in wrappers)
						{
							if (wrapper.object == child)
							{
								name = hashMap.getName(wrapper);
								break;
							}
						}
					}
					if (name != null)
						newNameOrder.push(name);
				}
				parentToBusyFlagMap[uiParent] = true;
				hashMap.setNameOrder(newNameOrder);
				delete parentToBusyFlagMap[uiParent];
				
				// setting the name order on the hash map may not trigger callbacks, but
				// the child order with respect to non-linkable children may have changed,
				// so always update child order after an IndexChangedEvent.
				uiParent.callLater(updateChildOrder, [uiParent, hashMap, keepLinkableChildrenOnTop]);
			};
			parentToListenerMap[uiParent] = listener;
			uiParent.addEventListener(IndexChangedEvent.CHILD_INDEX_CHANGE, listener);
		}
		
		/**
		 * This function will undo the linking done by linkUIComponents(uiParent, hashMap).
		 * @param uiParent The uiParent parameter for a previous call to linkUIComponents().
		 * @param hashMap The hashMap parameter for a previous call to linkUIComponents().
		 */
		public static function unlinkDisplayObjects(uiParent:UIComponent, hashMap:ILinkableHashMap):void
		{
			if (parentToListenerMap[uiParent] !== undefined)
			{
				hashMap.childListCallbacks.removeCallback(linkFunctionCache.remove(uiParent, hashMap) as Function);
				for each (var child:ILinkableDisplayObject in hashMap.getObjects(ILinkableDisplayObject))
					getCallbackCollection(child).removeCallback(linkFunctionCache.remove(uiParent, child) as Function);
				
				uiParent.removeEventListener(IndexChangedEvent.CHILD_INDEX_CHANGE, parentToListenerMap[uiParent]);
				var numChildren:int = uiParent.numChildren;
				for (var i:int = 0; i < numChildren; i++)
				{
					var uiChild:DisplayObject = uiParent.getChildAt(i);
					var listener:Function = childToEventListenerMap[uiChild] as Function;
					if (listener == null)
						continue;
					uiChild.removeEventListener(Event.ADDED, listener);
					uiChild.removeEventListener(Event.REMOVED, listener);
					delete childToEventListenerMap[uiChild];
				}
			}
		}
		
		/**
		 * This maps a UIComponent to a listener function created by linkUIComponents().
		 */		
		private static const parentToListenerMap:Dictionary = new Dictionary(true); // weak links to be gc-friendly
		
		/**
		 * This maps a parent to a Boolean value which indicates whether
		 * or not UIUtils is busy processing some event for that parent.
		 */
		private static const parentToBusyFlagMap:Dictionary = new Dictionary(true); // weak links to be gc-friendly

		/**
		 * This maps a child UIComponent to a FlexEvent.REMOVE event listener.
		 */
		private static const childToEventListenerMap:Dictionary = new Dictionary(true); // weak links to be gc-friendly
		
		/**
		 * This function will add a sessioned UIComponent to a parent UIComponent.
		 * @param uiParent The parent UIComponent to add a child to.
		 * @param hashMap A LinkableHashMap containing a dynamically created UIComponent.
		 * @param childName The name of a child in the hashMap.
		 */
		private static function addChild(uiParent:UIComponent, hashMap:ILinkableHashMap, childName:String, keepLinkableChildrenOnTop:Boolean):void
		{
			// Children will not be displayed properly unless the parent is on the stage when the children are added.
			if (!uiParent.initialized || !uiParent.stage)
			{
				uiParent.callLater(addChild, arguments);
				return;
			}
			
			var childObject:ILinkableObject = hashMap.getObject(childName);
			
			// special case: ILinkableDisplayObject
			if (childObject is ILinkableDisplayObject)
			{
				(childObject as ILinkableDisplayObject).parent = uiParent;
				
				var callback:Function = function():void { updateChildOrder(uiParent, hashMap, keepLinkableChildrenOnTop); };
				linkFunctionCache.set(uiParent, childObject, callback);
				
				getCallbackCollection(childObject).addImmediateCallback(uiParent, callback, true);
				return;
			}
			
			var uiChild:DisplayObject = childObject as DisplayObject;
			// stop if the child was already removed from the hash map
			if (uiChild == null)
				return;

			// When the child is added to the parent, the child order should be updated.
			// When the child is removed from the parent with removeChild() or removeChildAt(), it should be disposed.
			var listenLater:Function = function(event:Event):void
			{
				if (event.target == uiChild && !objectWasDisposed(uiChild))
				{
					if (event.type == Event.ADDED)
					{
						if (uiChild.parent == uiParent)
							updateChildOrder(uiParent, hashMap, keepLinkableChildrenOnTop);
					}
					else if (event.type == Event.REMOVED && !(childObject is ILinkableDisplayObject))
					{
						if (uiChild.parent != uiParent)
							hashMap.removeObject(childName);
					}
				}
			};
			var listener:Function = function (event:Event):void
			{
				// need to call later because Spark components use removeChild and addChildAt inside the setElementIndex function.
				uiParent.callLater(listenLater, arguments);
			};
			uiChild.addEventListener(Event.ADDED, listener);
			uiChild.addEventListener(Event.REMOVED, listener);
			childToEventListenerMap[uiChild] = listener; // save a pointer so the event listener can be removed later.
			
			if (uiParent == uiChild.parent)
				updateChildOrder(uiParent, hashMap, keepLinkableChildrenOnTop);
			else
				spark_addChild(uiParent, uiChild);
		}
		
		public static function spark_numChildren(parent:DisplayObjectContainer):int
		{
			if (parent is IVisualElementContainer)
				return (parent as IVisualElementContainer).numElements;
			else
				return parent.numChildren;
		}
		
		public static function spark_addChild(parent:DisplayObjectContainer, child:DisplayObject):DisplayObject
		{
			if (child.parent && child.parent != parent)
			{
				_previousParents[child] = child.parent;
				spark_removeChild(child.parent, child);
			}
			
			if (parent is IVisualElementContainer)
			{
				if (child is IVisualElement)
					return (parent as IVisualElementContainer).addElement(child as IVisualElement) as DisplayObject;
				else
					throw new Error("parent is IVisualElementContainer, but child is not an IVisualElement");
			}
			else
				return parent.addChild(child);
		}
		
		public static function spark_removeChild(parent:DisplayObjectContainer, child:DisplayObject):DisplayObject
		{
			if (parent is IVisualElementContainer)
			{
				if (child is IVisualElement)
				{
					try
					{
						return (parent as IVisualElementContainer).removeElement(child as IVisualElement) as DisplayObject;
					}
					catch (e:Error)
					{
						if (e.errorID != 2025) // The supplied DisplayObject must be a child of the caller
							throw e;
					}
					return child;
				}
				else
					throw new Error("parent is IVisualElementContainer, but child is not an IVisualElement");
			}
			else
				return parent.removeChild(child);
		}
		
		public static function spark_addChildAt(parent:DisplayObjectContainer, child:DisplayObject, index:int):DisplayObject
		{
			if (child.parent && child.parent != parent)
			{
				_previousParents[child] = child.parent;
				spark_removeChild(child.parent, child);
			}
			
			if (parent is IVisualElementContainer)
			{
				if (child is IVisualElement)
					return (parent as IVisualElementContainer).addElementAt(child as IVisualElement, index) as DisplayObject;
				else
					throw new Error("parent is IVisualElementContainer, but child is not an IVisualElement");
			}
			else
				return parent.addChildAt(child, index);
		}
		
		public static function spark_removeChildAt(parent:DisplayObjectContainer, index:int):DisplayObject
		{
			if (parent is IVisualElementContainer)
				return (parent as IVisualElementContainer).removeElementAt(index) as DisplayObject;
			else
				return parent.removeChildAt(index);
		}
		
		public static function spark_getChildAt(parent:DisplayObjectContainer, index:int):DisplayObject
		{
			if (parent is IVisualElementContainer)
				return (parent as IVisualElementContainer).getElementAt(index) as DisplayObject;
			else
				return parent.getChildAt(index);
		}
		
		public static function spark_getChildIndex(parent:DisplayObjectContainer, child:DisplayObject):int
		{
			if (parent is IVisualElementContainer && child is IVisualElement)
			{
				if (child is IVisualElement)
					return (parent as IVisualElementContainer).getElementIndex(child as IVisualElement);
				else
					throw new Error("parent is IVisualElementContainer, but child is not an IVisualElement");
			}
			else
				return parent.getChildIndex(child);
		}
		
		public static function spark_setChildIndex(parent:DisplayObjectContainer, child:DisplayObject, index:int):void
		{
			if (parent is IVisualElementContainer && child is IVisualElement)
			{
				if (child is IVisualElement)
					(parent as IVisualElementContainer).setElementIndex(child as IVisualElement, index);
				else
					throw new Error("parent is IVisualElementContainer, but child is not an IVisualElement");
			}
			else
				parent.setChildIndex(child, index);
		}
		
		/**
		 * This function gets called when a LinkableHashMap changes that was previously linked with a DisplayObjectContainer through linkUIComponents().
		 * Any sessioned DisplayObjects that were added/removed/reordered will be handled here.
		 * @param uiParent A DisplayObjectContainer to synchronize with the given hashMap.
		 * @param hashMap A LinkableHashMap containing sessioned DisplayObjects to synchronize with the given uiParent.
		 */
		private static function handleHashMapChildListChange(uiParent:UIComponent, hashMap:ILinkableHashMap, keepLinkableChildrenOnTop:Boolean):void
		{
			if (hashMap.childListCallbacks.lastObjectRemoved)
			{
				var removedChild:DisplayObject = hashMap.childListCallbacks.lastObjectRemoved as DisplayObject;
				if (!removedChild)
					return;
				var listener:Function = childToEventListenerMap[removedChild] as Function;
				if (listener != null)
				{
					removedChild.removeEventListener(Event.ADDED, listener);
					removedChild.removeEventListener(Event.REMOVED, listener);
					delete childToEventListenerMap[removedChild];
				}
				// removeChild() gives an error if called twice
				try {
					uiParent.removeChild(removedChild);
				} catch (e:Error) { } // behavior still seems ok after twice-called removeChild()
			}
			else if (hashMap.childListCallbacks.lastObjectAdded)
			{
				addChild(uiParent, hashMap, hashMap.childListCallbacks.lastNameAdded, keepLinkableChildrenOnTop);
			}
			else if (!parentToBusyFlagMap[uiParent])
			{
				// order changed, so set z-order of all sessioned UIComponents
				uiParent.callLater(updateChildOrder, [uiParent, hashMap, keepLinkableChildrenOnTop]);
			}
		}
		/**
		 * This function updates the order of the children in the uiParent based on the session state.
		 * @param uiParent
		 * @param hashMap
		 * @param keepLinkableChildrenOnTop
		 */		
		private static function updateChildOrder(uiParent:UIComponent, hashMap:ILinkableHashMap, keepLinkableChildrenOnTop:Boolean):void
		{
			if (!uiParent.initialized)
			{
				uiParent.callLater(updateChildOrder, arguments);
				return;
			}
			
			var uiChild:DisplayObject;
			// get all child DisplayObjects we are interested in
			var uiChildren:Array = hashMap.getObjects();
			var i:int = uiChildren.length;
			while (i-- > 0)
			{
				var wrapper:ILinkableDisplayObject = uiChildren[i] as ILinkableDisplayObject;
				if (wrapper)
					uiChildren[i] = wrapper.object;
				if (!(uiChildren[i] is DisplayObject))
					uiChildren.splice(i, 1);
			}
			// stop if there are sessioned UIComponents that are not contained by the parent.
			for each (uiChild in uiChildren)
				if (uiChild && uiParent != uiChild.parent)
					return;

			parentToBusyFlagMap[uiParent] = true; // prevent sessioned name order from being set
			if (keepLinkableChildrenOnTop)
			{
				// set child index values in reverse order so all the sessioned children will appear on top
				var indexOffset:int = uiParent.numChildren - uiChildren.length;
				for (i = uiChildren.length; i--;)
				{
					uiChild = uiChildren[i] as DisplayObject;
					if (uiChild && uiParent == uiChild.parent && uiParent.getChildIndex(uiChild) != indexOffset + i)
						spark_setChildIndex(uiParent, uiChild, indexOffset + i);
				}
			}
			else
			{
				for (i = 0; i < uiChildren.length; i++)
				{
					uiChild = uiChildren[i] as DisplayObject;
					if (uiChild && uiParent == uiChild.parent && uiParent.getChildIndex(uiChild) != i)
						spark_setChildIndex(uiParent, uiChild, i);
				}
			}
			delete parentToBusyFlagMap[uiParent];
		}
	}
}
