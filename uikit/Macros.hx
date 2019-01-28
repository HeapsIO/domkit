package uikit;
#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import uikit.Error;
#end

class Macros {
	#if macro

	@:persistent static var COMPONENTS = new Map<String, uikit.MetaComponent>();
	@:persistent static var componentsType : ComplexType;
	static var __ = addComponents(); // each compilation

	public static function registerComponentClass( path : String ) {
		var path = path.split(".");
		var sub = path[path.length - 2];
		registerComponent(TPath({
			pack : path,
			sub : sub != null && sub.charCodeAt(0) >= "A".code && sub.charCodeAt(0) <= "Z".code ? path.pop() : null,
			name : path.pop()
		}));
	}

	public static function registerComponent( type : ComplexType ) {
		var pos = Context.currentPos();
		var t = Context.resolveType(type, pos);
		if( componentsType == null ) {
			componentsType = type;
			switch( t ) {
			case TInst(c,_):
				for( i in c.get().interfaces )
					if( i.t.toString() == "uikit.ComponentDecl" )
						componentsType = haxe.macro.Tools.TTypeTools.toComplexType(i.params[0]);
			default:
			}
		}
		try {
			var mt = new uikit.MetaComponent(componentsType, t);
			componentsType = mt.componentsType;
			var td = mt.buildRuntimeComponent();
			Context.defineType(td, mt.getModulePath());
			COMPONENTS.set(mt.name, mt);
		} catch( e : uikit.MetaComponent.MetaError ) {
			Context.error(e.message, e.position);
		}
	}

	static function addComponents() {
		haxe.macro.Context.onAfterTyping(function(_) {
			for( mt in COMPONENTS ) {
				try {
					Context.resolveType(mt.getRuntimeComponentType(), Context.currentPos());
				} catch( e : Dynamic ) {
					Context.error("Error "+e, @:privateAccess mt.classType.pos);
				}
			}
		});
	}

	static function buildComponentsInit( m : MarkupParser.Markup, fields : Array<haxe.macro.Expr.Field>, pos : Position, isRoot = false ) : Expr {
		switch (m.kind) {
		case Node(name):
			var comp = COMPONENTS.get(name);
			if( comp == null )
				error("Unknown component "+name, m.pmin, m.pmax);
			var avalues = [];
			var aexprs = [];
			for( attr in m.attributes ) {
				var p = Property.get(attr.name, false);
				if( p == null ) {
					error("Unknown property "+attr.name, attr.pmin, attr.pmin + attr.name.length);
					continue;
				}
				var h = comp.getHandler(p);
				if( h == null ) {
					error("Component "+comp.name+" does not handle property "+p.name, attr.pmin, attr.pmin + attr.name.length);
					continue;
				}
				switch( attr.value ) {
				case RawValue(aval):
					var css = try new CssParser().parseValue(aval) catch( e : Error ) error("Invalid CSS ("+e.message+")", attr.vmin + e.pmin, attr.vmin + e.pmax);
					try {
						if( h.parser == null ) throw new Property.InvalidProperty("Null parser");
						h.parser(css);
					} catch( e : Property.InvalidProperty ) {
						error("Invalid "+comp.name+"."+p.name+" value '"+aval+"'"+(e.message == null ? "" : " ("+e.message+")"), attr.vmin, attr.pmax);
					}
					avalues.push({ attr : attr.name, value : aval });
				case Code(e):
					var mc = Std.instance(comp, MetaComponent);
					var eset = null;
					while( mc != null ) {
						eset = mc.setExprs.get(p.name);
						if( eset != null ) break;
						mc = cast(mc.parent, MetaComponent);
					}
					aexprs.push(macro var attrib = $e);
					aexprs.push({ expr : EMeta({ pos : e.pos, name : ":privateAccess" }, { expr : ECall(eset,[macro cast tmp.obj,macro attrib]), pos : e.pos }), pos : e.pos });
					aexprs.push(macro @:privateAccess tmp.initStyle($v{p.name},attrib));
				}
			}
			var attributes = { expr : EObjectDecl([for( m in avalues ) { field : m.attr, expr : { expr : EConst(CString(m.value)), pos : pos } }]), pos : pos };
			var ct = comp.baseType;
			var exprs : Array<Expr> = if( isRoot )
				[
					(macro document = new uikit.Document()),
					(macro var tmp : uikit.Element<$componentsType> = uikit.Element.create($v{name},$attributes,(null:uikit.Element<$componentsType>),(this : $ct))),
					(macro document.elements.push(tmp)),
				];
			else
				[macro var tmp = uikit.Element.create($v{name},$attributes, tmp)];
			for( a in m.attributes )
				if( a.name == "name" ) {
					var field = switch( a.value ) {
					case RawValue(v): v;
					default: continue;
					}
					exprs.push(macro this.$field = cast tmp.obj);
					fields.push({
						name : field,
						access : [APublic],
						pos : makePos(pos, a.pmin, a.pmax),
						kind : FVar(ct),
					});
				}
			for( e in aexprs )
				exprs.push(e);
			for( c in m.children ) {
				var e = buildComponentsInit(c, fields, pos);
				if( e != null ) exprs.push(e);
			}
			return macro $b{exprs};
		case Text(text):
			var text = StringTools.trim(text);
			if( text == "" ) return null;
			return macro {
				var tmp = uikit.Element.create("text",null,tmp);
				tmp.setAttribute("text",VString($v{text}));
			};
		case CodeBlock(expr):
			var expr = Context.parseInlineString(expr,makePos(pos, m.pmin, m.pmax));
			replaceLoop(expr, function(m) return buildComponentsInit(m, fields, pos));
			return expr;
		}
	}

	static function replaceLoop( e : Expr, callb : MarkupParser.Markup -> Expr ) {
		switch( e.expr ) {
		case EMeta({ name : ":markup" },{ expr : EConst(CString(str)) }):
			var p = new MarkupParser();
			var pinf = Context.getPosInfos(e.pos);
			var root = p.parse(str,pinf.file,pinf.min).children[0];
			e.expr = callb(root).expr;
		default:
			haxe.macro.ExprTools.iter(e,function(e) replaceLoop(e,callb));
		}
	}

	static function lookupInterface( c : haxe.macro.Type.Ref<haxe.macro.Type.ClassType>, name : String ) {
		while( true ) {
			var cg = c.get();
			for( i in cg.interfaces ) {
				if( i.t.toString() == name )
					return true;
				if( lookupInterface(i.t, name) )
					return true;
			}
			var sup = cg.superClass;
			if( sup == null )
				break;
			c = sup.t;
		}
		return false;
	}

	public static function buildObject() {
		var cl = Context.getLocalClass().get();
		var fields = Context.getBuildFields();
		for( f in fields )
			if( f.name == "SRC" ) {
				switch( f.kind ) {
				case FVar(_,{ expr : EMeta({ name : ":markup" },{ expr : EConst(CString(str)) }), pos : pos }):
					try {
						var p = new MarkupParser();
						var pinf = Context.getPosInfos(pos);
						var root = p.parse(str,pinf.file,pinf.min).children[0];

						var initExpr = buildComponentsInit(root, fields, pos, true);

						if( cl.superClass != null && !lookupInterface(cl.superClass.t,"h2d.uikit.Object") )
							fields = fields.concat((macro class {
								public var document : uikit.Document<$componentsType>;
								public function setStyle( style : uikit.CssStyle ) {
									document.setStyle(style);
								}
							}).fields);

						var found = false;
						for( f in fields )
							if( f.name == "new" ) {
								switch( f.kind ) {
								case FFun(f):
									function replace( e : Expr ) {
										switch( e.expr ) {
										case ECall({ expr : EConst(CIdent("initComponent")) },[]): e.expr = initExpr.expr; found = true;
										default: haxe.macro.ExprTools.iter(e, replace);
										}
									}
									replace(f.expr);
									if( !found ) Context.error("Constructor missing initComponent() call", f.expr.pos);
									break;
								default:
								}
							}
						if( !found )
							Context.error("Missing constructor", Context.currentPos());

					} catch( e : Error ) {
						Context.error(e.message, makePos(pos,e.pmin,e.pmax));
					}
					fields.remove(f);
					break;
				default:
				}
			}
		return fields;
	}


	static function error( msg : String, pmin : Int, pmax : Int = -1 ) : Dynamic {
		throw new Error(msg, pmin, pmax);
	}

	static function makePos( p : Position, pmin : Int, pmax : Int ) {
		var p0 = Context.getPosInfos(p);
		return Context.makePosition({ min : p0.min + pmin, max : p0.min + pmax, file : p0.file });
	}

	#end

}