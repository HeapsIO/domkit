package domkit;

class RuleStyle {
	public var p : Property;
	public var value : CssValue;
	public var lastHandler : Component.PropertyHandler<Dynamic,Dynamic>;
	public var lastValue : Dynamic;
	public function new(p,value) {
		this.p = p;
		this.value = value;
	}
}

class RuleTransition {
	public var p : Property;
	public var time : Float;
	public var curve : CssParser.Curve;
	public var next : RuleTransition;
	public function new(p, time, curve) {
		this.p = p;
		this.time = time;
		this.curve = curve;
	}
}

class Rule {
	public var id : Int;
	public var priority : Int;
	public var cl : CssParser.CssClass;
	public var style : Array<RuleStyle>;
	public var transitions : Array<RuleTransition>;
	public var next : Rule;
	public function new() {
	}
}

class CssTransition {
	public var properties : Properties<Dynamic>;
	public var trans : RuleTransition;
	public var handler : Component.PropertyHandler<Dynamic,Dynamic>;
	public var vstart : Dynamic;
	public var vtarget : Dynamic;
	public var progress : Float;
	public function new() {
	}
}

#if hl
@:forward(fill)
abstract FastBytes(hl.Bytes) to hl.Bytes {
	public inline function get(index) return this.getUI8(index);
	public inline function set(index,value) this.setUI8(index, value);
	public inline function sub(index,len) : FastBytes return cast this.sub(index, len);
	@:from public static inline function fromBytes(bytes:haxe.io.Bytes) : FastBytes {
		return cast @:privateAccess bytes.b;
	}
}

class BytesCell<T> {
	public var bytes : hl.Bytes;
	public var value : T;
	public var next : BytesCell<T>;
	public function new(bytes,value,next) {
		this.bytes = bytes;
		this.value = value;
		this.next = next;
	}
}

abstract BytesMap<T>(Map<Int,BytesCell<T>>) {

	static var BUF = new hl.Bytes(4);

	public function new() {
		this = [];
	}

	inline function makeHash( bytes : hl.Bytes, len : Int ) {
		var buf = BUF;
		hl.Format.digest(buf,bytes,len,3);
		return buf.getI32(0);
	}

	public inline function get( bytes : hl.Bytes, len : Int ) {
		var h = makeHash(bytes, len);
		var c = this.get(h);
		var value = null;
		while( c != null ) {
			if( c.bytes.compare(0, bytes, 0, len) == 0 ) {
				value = c.value;
				break;
			}
			c = c.next;
		}
		return value;
	}

	public inline function set( bytes : hl.Bytes, len : Int, value ) {
		var h = makeHash(bytes, len);
		var c = new BytesCell(bytes.sub(0,len), value, this.get(h));
		this.set(h, c);
	}

}
#else

typedef FastBytes = haxe.io.Bytes;

#end

class CssData {

	public static var CID = 0;
	public static var COMPONENTS = [];

	public var rules : Array<Rule>;
	public var bytesSize : Int;
	public var needsInit = false;

	var rulesByComp : #if hl BytesMap<Array<Rule>> #else Map<String,Array<Rule>> #end;

	public function new() {
		rules = [];
	}

	function sortByPriority(r1:Rule, r2:Rule) {
		var dp = r2.priority - r1.priority;
		return dp == 0 ? r2.id - r1.id : dp;
	}

	public function init() {
		if( needsInit ) {
			needsInit = false;
			rules.sort(sortByPriority);
			// attribute component ids
			var prev = COMPONENTS.length;
			for( r in rules ) {
				var cl = r.cl;
				while( cl != null ) {
					if( cl.component != null && cl.component.id < 0 ) {
						COMPONENTS.push(cl.component);
						cl.component.id = CID++;
					}
					cl = cl.parent;
				}
			}
			// add all children
			while( prev < COMPONENTS.length ) {
				var c = COMPONENTS[prev++];
				for( c2 in @:privateAccess Component.COMPONENTS ) {
					if( c2.parent == c && c2.id < 0 ) {
						COMPONENTS.push(c2);
						c2.id = CID++;
					}
				}
			}
			bytesSize = -1;
		}
		var reqSize = (CssData.CID + 7) & ~7;
		if( reqSize > bytesSize ) {
			bytesSize = reqSize;
			rulesByComp = #if hl new BytesMap() #else new Map() #end;
		}
	}

	public inline function getCache( bits : FastBytes ) : Array<Rule> {
		return rulesByComp.get(#if hl bits, bytesSize #else bits.toHex() #end);
	}

	public inline function setCache( bits : FastBytes, value : Array<Rule> ) {
		rulesByComp.set(#if hl bits, bytesSize #else bits.toHex() #end, value);
	}

	public function add( sheet : CssParser.CssSheet ) {
		for( r in sheet ) {
			for( cl in r.classes ) {
				var nids = 0, nothers = 0, nnodes = 0;
				var c = cl;
				while( c != null ) {
					if( c.id != null ) nids++;
					if( c.component != null ) {
						nnodes += 32;
						var k = c.component.parent;
						while( k != null ) {
							nnodes++;
							k = k.parent;
						}
					}
					if( c.pseudoClasses != None ) {
						var i = c.pseudoClasses.toInt();
						while( i != 0 ) {
							if( i & 1 != 0 ) nothers++;
							i >>>= 1;
						}
					}
					if( c.className != null ) nothers++;
					c = c.parent;
				}
				var priority = (nids << 24) | (nothers << 17) | nnodes;
				var important = null;
				var rule = new Rule();
				rule.id = rules.length;
				rule.cl = cl;
				rule.style = [];
				for( s in r.style )
					switch( s.value ) {
					case VLabel("important", val):
						if( important == null ) important = [];
						important.push(new RuleStyle(s.p,val));
					default:
						rule.style.push(new RuleStyle(s.p,s.value));
					}
				rule.priority = priority;
				if( r.transitions != null ) {
					rule.transitions = [];
					for( t in r.transitions )
						rule.transitions.push(new RuleTransition(t.p, t.time, t.curve));
				}
				if( rule.style.length > 0 )
					rules.push(rule);
				if( important != null ) {
					var tr = rule.transitions;
					rule.transitions = null;
					var rule = new Rule();
					rule.id = rules.length;
					rule.cl = cl;
					rule.style = important;
					rule.priority = priority + (1 << 30);
					rule.transitions = tr;
					rules.push(rule);
				}
			}
		}
		needsInit = true;
	}

}

@:access(domkit.Properties)
class CssStyle {

	static var TAG = 0;

	public var data : CssData;
	public var useSmartCache = true;
	var currentTransitions : Array<CssTransition> = [];
	var componentsBits : FastBytes;
	var compSize : Int;

	public function new() {
		data = new CssData();
	}

	function onInvalidProperty( e : Properties<Dynamic>, s : RuleStyle, msg : String ) {
	}

	function addTransition( e : Properties<Dynamic>, trans : RuleTransition, h : Component.PropertyHandler<Dynamic,Dynamic>, vtarget : Dynamic ) {
		if( e.transitionValues == null ) e.transitionValues = new Map();
		var vstart : Dynamic = e.transitionValues.get(trans.p.id);
		if( vstart == null ) vstart = h.defaultValue;
		if( vtarget == null ) vtarget = h.defaultValue;
		if( h.transition == null && !Std.isOfType(vtarget == null ? vstart : vtarget,Float) )
			throw "Cannot add transition on "+e.component.name+"."+trans.p.name+" : unsupported value "+Std.string(vtarget == null ? vstart : vtarget);
		for( c in currentTransitions ) {
			if( c.properties == e && c.trans.p == trans.p ) {
				// return to same value ?
				if( c.vstart == vtarget ) {
					c.vstart = c.vtarget;
					c.progress = 1 - c.progress;
				} else {
					c.vstart = vstart;
					c.progress = 0; // reset progress (unknown "distance")
				}
				c.vtarget = vtarget;
				return;
			}
		}
		var t = new CssTransition();
		t.properties = e;
		t.handler = h;
		t.trans = trans;
		t.vstart = vstart;
		t.vtarget = vtarget;
		t.progress = 0;
		e.transitionCount++;
		currentTransitions.push(t);
	}

	inline function setCompBit( id : Int ) {
		if( id < 0 )
			return -1;
		var pos = id >> 3;
		var v = componentsBits.get(pos);
		var msk = 1 << (id & 7);
		if( (v & msk) == 0 ) {
			componentsBits.set(pos,v | msk);
			return v;
		}
		return -1;
	}

	function getCurrentRules() {
		var rules = data.getCache(componentsBits);
		if( rules == null ) {
			// complete bits with superclasses
			var prev = componentsBits;
			var change = false;
			for( c in CssData.COMPONENTS ) {
				if( componentsBits.get(c.id>>3)&(1<<(c.id&7)) != 0 ) {
					var p = c.parent;
					while( p != null ) {
						var v = setCompBit(p.id);
						if( v >= 0 && !change ) {
							change = true;
							prev = componentsBits.sub(0, compSize);
							prev.set(p.id>>3, v);
						}
						p = p.parent;
					}
				}
			}
			if( change )
				rules = data.getCache(componentsBits);
			if( rules == null ) {
				rules = [];
				for( r in data.rules ) {
					var cl = r.cl;
					var ignore = false;
					while( cl != null ) {
						if( cl.component != null ) {
							var id = cl.component.id;
							if( componentsBits.get(id>>3)&(1<<(id&7)) == 0 ) {
								ignore = true;
								break;
							}
						}
						cl = cl.parent;
					}
					if( ignore ) continue;
					rules.push(r);
				}
				if( change )
					data.setCache(componentsBits,rules);
			}
			componentsBits = prev;
			data.setCache(componentsBits,rules);
		}
		return rules;
	}

	function applyStyle( e : Properties<Dynamic>, force : Bool ) {
		data.init();
		if( !useSmartCache ) {
			applyStyleRec(e, force, data.rules);
			return;
		}
		if( compSize < data.bytesSize ) {
			compSize = data.bytesSize;
			componentsBits = haxe.io.Bytes.alloc(compSize);
		}
		componentsBits.fill(0,compSize,0);
		var cur = e.parent;
		while( cur != null ) {
			setCompBit(cur.component.id);
			cur = cur.parent;
		}
		applyStyleRec(e, force, null);
	}

	function applyStyleRec( e : Properties<Dynamic>, force : Bool, rules : Array<Rule> ) {

		var prev = -1;
		if( useSmartCache ) {
			prev = setCompBit(e.component.id);
			if( prev >= 0 ) rules = null;
		}

		if( e.needStyleRefresh || force ) {
			var firstInit = e.firstInit;
			e.firstInit = false;
			e.needStyleRefresh = false;
			var head = null, transHead : RuleTransition = null;
			var tag = ++TAG;
			var prevTransCount = e.transitionCount;
			for( p in e.style )
				p.p.tag = tag;

			inline function addTransition(p:Property,h,target:Dynamic) {
				var t = transHead;
				while( true ) {
					if( t.p == p ) {
						this.addTransition(e, t, h, target);
						break;
					}
					t = t.next;
				}
			}

			if( rules == null )
				rules = getCurrentRules();

			for( r in rules ) {
				if( !ruleMatch(r.cl,e) ) continue;
				var match = false;
				for( p in r.style )
					if( p.p.tag != tag ) {
						p.p.tag = tag;
						match = true;
					}
				if( r.transitions != null ) {
					for( t in r.transitions ) {
						if( t.p.transTag != tag ) {
							t.p.transTag = tag;
							t.next = transHead;
							transHead = t;
						}
					}
				}
				if( match ) {
					r.next = head;
					head = r;
				}
			}

			/*
			// debug check that the filtering doesn't forget any rule
			for( r in data.rules ) {
				if( ruleMatch(r.cl,e) && rules.indexOf(r) < 0 ) {
					var comps = [];
					for( id in 0...CssData.CID ) {
						if( componentsBits.get(id>>3)&(1<<(id&7)) != 0 )
							comps.push(CssData.COMPONENTS[id]);
					}
					throw "assert";
				}
			}*/

			// reset to default previously set properties that are no longer used
			var changed = false;
			var ntag = ++TAG;
			var i = e.currentSet.length - 1;
			while( i >= 0 ) {
				var p = e.currentSet[i--];
				if( p.tag == tag )
					p.tag = ntag;
				else {
					changed = true;
					e.currentSet.remove(p);
					if( e.currentValues != null ) e.currentValues.splice(i+1,1);
					var h = e.component.getHandler(p);
					if( p.transTag == tag ) {
						p.transTag = ntag;
						addTransition(p, h, null);
						continue;
					}
					h.apply(e.obj,h.defaultValue);
					if( p.hasTransition ) e.transitionValues.set(p.id, null);
				}
			}
			// apply new properties
			var r = head;
			while( r != null ) {
				for( p in r.style ) {
					var pr = p.p;
					var h = e.component.getHandler(pr);
					if( h == null ) {
						onInvalidProperty(e, p, "Unsupported property");
						continue;
					}

					if( p.lastHandler != h ) {
						try {
							var value = h.parser(p.value);
							p.lastHandler = h;
							p.lastValue = value;
						} catch( err : Property.InvalidProperty ) {
							// invalid property
							onInvalidProperty(e, p, err.message);
							continue;
						}
					}

					if( (pr.transTag == tag || pr.transTag == ntag) && !firstInit ) {
						pr.transTag = ntag;
						addTransition(pr, h, p.lastValue);
					} else {
						h.apply(e.obj, p.lastValue);
						changed = true;

						if( pr.hasTransition ) {
							if( e.transitionValues == null ) e.transitionValues = new Map();
							e.transitionValues.set(pr.id, p.lastValue);
							pr.transTag = tag - 1;
						}
					}

					if( pr.tag != ntag ) {
						if( Properties.KEEP_VALUES ) {
							e.initCurrentValues();
							e.currentValues.push(p.value);
						}
						e.currentSet.push(pr);
						pr.tag = ntag;
					} else {
						if( Properties.KEEP_VALUES ) {
							e.initCurrentValues();
							e.currentValues[e.currentSet.indexOf(pr)] = p.value;
						}
					}
				}
				var n = r.next;
				r.next = null;
				r = n;
			}

			// cancel transitions that are no longer valid
			if( prevTransCount > 0 ) {
				var i = 0;
				var max = currentTransitions.length;
				while( i < max ) {
					var c = currentTransitions[i++];
					if( c.properties == e && c.trans.p.transTag != ntag ) {
						currentTransitions.remove(c);
						e.transitionCount--;
						i--;
						max--;
						if( c.trans.p.tag != ntag )
							e.transitionValues.set(c.trans.p.id, c.handler.defaultValue);
					}
				}
			}

			// transitions set on unset values : define default value
			var t = transHead;
			while( t != null ) {
				if( t.p.transTag == tag && e.transitionValues != null )
					e.transitionValues.set(t.p.id, null);
				t = t.next;
			}

			// reapply style properties
			if( changed )
				for( p in e.style ) {
					var h = e.component.getHandler(p.p);
					if( h != null ) h.apply(e.obj, p.value);
				}
			// parent style has changed, we need to sync children
			force = true;
		}
		var obj : Model<Dynamic> = e.obj;
		for( c in obj.getChildren() ) {
			var c : Model<Dynamic> = c;
			if( c.dom == null )
				continue;
			applyStyleRec(c.dom, force, rules);
		}

		if( prev >= 0 )
			componentsBits.set(e.component.id >> 3, prev);
	}

	public function updateTime( dt : Float ) {
		var i = 0;
		var max = currentTransitions.length;
		while( i < max ) {
			var c = currentTransitions[i++];
			c.progress += dt / c.trans.time;
			var current : Dynamic = null;
			if( c.progress > 1 ) {
				c.progress = 1;
				current = c.vtarget;
				c.properties.transitionCount--;
				currentTransitions.remove(c);
				i--;
				max--;
			} else if( c.handler.transition != null )
				current = c.handler.transition(c.vstart, c.vtarget, c.trans.curve.interpolate(c.progress));
			else {
				var vstart : Float = c.vstart;
				var vtarget : Float = c.vtarget;
				current = (vtarget - vstart) * c.trans.curve.interpolate(c.progress) + vstart;
			}
			c.handler.apply(c.properties.obj, current);
			c.properties.transitionValues.set(c.trans.p.id, current);
		}
	}

	public function add( sheet : CssParser.CssSheet ) {
		data.add(sheet);
	}

	public static function ruleMatch( c : CssParser.CssClass, e : Properties<Dynamic> ) {
		if( c.id != null && c.id != e.id )
			return false;
		if( c.pseudoClasses != None ) {
			if( c.pseudoClasses.has(HOver) && !e.hover )
				return false;
			if( c.pseudoClasses.has(Active) && !e.active )
				return false;
			if( c.pseudoClasses.has(Disabled) && !e.disabled )
				return false;
			if( c.pseudoClasses.has(NeedChildren) ) {
				var parent = e.parent;
				if( parent == null )
					return false;
				var children = parent.obj.getChildren();
				if( c.pseudoClasses.has(FirstChild) && children[0] != e.obj )
					return false;
				if( c.pseudoClasses.has(LastChild) && children[children.length - 1] != e.obj )
					return false;
				if( c.pseudoClasses.has(Odd) && children.indexOf(e.obj) & 1 == 0 )
					return false;
				if( c.pseudoClasses.has(Even) && children.indexOf(e.obj) & 1 != 0 )
					return false;
			}
		}
		if( c.component != null && !e.component.isOfType(c.component) )
			return false;
		if( c.className != null ) {
			if( e.classes == null )
				return false;
			var found = false;
			for( cc in e.classes )
				if( cc == c.className ) {
					found = true;
					break;
				}
			if( !found )
				return false;
			if( c.extraClasses != null ) {
				for( cname in c.extraClasses ) {
					var found = false;
					for( cc in e.classes )
						if( cc == cname ) {
							found = true;
							break;
						}
					if( !found )
						return false;
				}
			}
		}
		if( c.parent != null ) {
			var p = e.parent;
			switch( c.relation ) {
			case None:
				while( p != null ) {
					if( ruleMatch(c.parent, p) )
						break;
					p = p.parent;
				}
				if( p == null )
					return false;
			case ImmediateChildren:
				return p != null && ruleMatch(c.parent, p);
			}
		}
		return true;
	}

}
