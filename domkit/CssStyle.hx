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

class Rule {
	public var id : Int;
	public var priority : Int;
	public var cl : CssParser.CssClass;
	public var style : Array<RuleStyle>;
	public var next : Rule;
	public function new() {
	}
}

@:access(domkit.Properties)
class CssStyle {

	static var TAG = 0;

	var rules : Array<Rule>;
	var needSort = true;

	public function new() {
		rules = [];
	}

	function sortByPriority(r1:Rule, r2:Rule) {
		var dp = r2.priority - r1.priority;
		return dp == 0 ? r2.id - r1.id : dp;
	}

	function onInvalidProperty( e : Properties<Dynamic>, s : RuleStyle, msg : String ) {
	}

	function applyStyle( e : Properties<Dynamic>, force : Bool ) {
		if( needSort ) {
			needSort = false;
			rules.sort(sortByPriority);
		}
		if( e.needStyleRefresh || force ) {
			e.needStyleRefresh = false;
			var head = null;
			var tag = ++TAG;
			for( p in e.style )
				p.p.tag = tag;
			for( r in rules ) {
				if( !ruleMatch(r.cl,e) ) continue;
				var match = false;
				for( p in r.style )
					if( p.p.tag != tag ) {
						p.p.tag = tag;
						match = true;
					}
				if( match ) {
					r.next = head;
					head = r;
				}
			}
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
					h.apply(e.obj,h.defaultValue);
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
					h.apply(e.obj, p.lastValue);
					changed = true;
					if( pr.tag != ntag ) {
						if( Properties.KEEP_VALUES ) {
							e.initCurrentValues();
							e.currentValues.push(p.value);
						}
						e.currentSet.push(pr);
						pr.tag = ntag;
					}
				}
				var n = r.next;
				r.next = null;
				r = n;
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
			applyStyle(c.dom, force);
		}
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
				if( rule.style.length > 0 )
					rules.push(rule);
				if( important != null ) {
					var rule = new Rule();
					rule.id = rules.length;
					rule.cl = cl;
					rule.style = important;
					rule.priority = priority + (1 << 30);
					rules.push(rule);
				}
			}
		}
		needSort = true;
	}

	public static function ruleMatch( c : CssParser.CssClass, e : Properties<Dynamic> ) {
		if( c.id != null && c.id != e.id )
			return false;
		if( c.pseudoClasses != None ) {
			if( c.pseudoClasses.has(HOver) && !e.hover )
				return false;
			if( c.pseudoClasses.has(Active) && !e.active )
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
