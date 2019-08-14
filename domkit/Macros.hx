package domkit;
#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import domkit.Error;
using haxe.macro.Tools;

typedef ComponentData = {
	var declaredIds : Map<String,Bool>;
	var fields : Array<haxe.macro.Expr.Field>;
}

#end

class Macros {
	#if macro

	@:persistent static var COMPONENTS = new Map<String, domkit.MetaComponent>();
	@:persistent static var componentsSearchPath : Array<String> = ["h2d.domkit.BaseComponents.$Comp"];
	@:persistent static var componentsType : ComplexType;
	@:persistent static var preload : Array<String> = [];
	static var RESOLVED_COMPONENTS = new Map();

	public static dynamic function processMacro( id : String, args : Null<Array<haxe.macro.Expr>>, pos : haxe.macro.Expr.Position ) : MarkupParser.Markup {
		return null;
	}

	public static function registerComponentsPath( path : String ) {
		if( componentsSearchPath.indexOf(path) < 0 )
			componentsSearchPath.push(path);
	}

	public static function checkCSS( file : String ) {
		if( Context.defined("display") ) return;
		file = Context.resolvePath(file);
		var content = sys.io.File.getContent(file);
		inline function error(msg, pmin,pmax) {
			Context.error(msg, Context.makePosition({ file : file, min : pmin, max : pmax }));
		}
		try {
			var parser = new CssParser();
			var rules = parser.parseSheet(content);
			var components : Array<Component<Dynamic,Dynamic>> = [for( c in COMPONENTS ) c];
			inline function height(c:Component<Dynamic,Dynamic>) {
				var h = 0;
				do {
					c = c.parent;
					h++;
				} while( c != null );
				return h;
			}
			components.sort(function(c1,c2) return height(c1) - height(c2));
			parser.check(rules, components);
			for( w in parser.warnings )
				error(w.msg, w.pmin, w.pmax);
		} catch( e : Error ) {
			error(e.message, e.pmin, e.pmax);
		}
	}

	static function loadComponent( name : String, pmin : Int, pmax : Int ) {
		var c = RESOLVED_COMPONENTS.get(name);
		if( c != null ) {
			if( c.path != null ) Context.getType(c.path);
			return c.c;
		}
		var lastError = null;
		var uname = MetaComponent.componentNameToClass(name);
		for( p in componentsSearchPath ) {
			var path = p.split("$").join(uname);
			var t = try Context.getType(path) catch( e : Dynamic ) continue;
			switch( t.follow() ) {
			case TInst(c,_): c.get(); // force build
			default:
			}
			var c = COMPONENTS.get(name);
			if( c == null ) {
				lastError = t;
				continue;
			}
			RESOLVED_COMPONENTS.set(name, { c : c, path : path });
			return c;
		}
		if( lastError != null )
			error(lastError.toString()+" does not define component "+name, pmin, pmax);
		return error("Could not load component '"+name+"'", pmin, pmax);
	}

	static function buildComponentsInit( m : MarkupParser.Markup, data : ComponentData, pos : Position, isRoot = false ) : Expr {
		switch (m.kind) {
		case Node(name):
			var comp = loadComponent(name, m.pmin, m.pmin+name.length);
			var args = comp.getConstructorArgs();
			var eargs = [];
			if( m.arguments == null ) m.arguments = [];
			if( m.attributes == null ) m.attributes = [];
			if( m.children == null ) m.children = [];
			if( isRoot ) {
				if( m.arguments.length > 0 )
					error("Arguments should be passed in super constructor", m.pmin, m.pmax);
			} else {
				if( m.arguments.length > args.length )
					error("Component requires "+args.length+" arguments ("+[for( a in args ) a.name].join(", ")+")", m.pmin, m.pmin + name.length);
				for( i in 0...args.length ) {
					var a = args[i];
					var cur = m.arguments[i];
					if( cur == null ) {
						if( !a.opt )
							error("Missing argument "+a.name+"("+a.type.toString()+")", m.pmin, m.pmin + name.length);
						continue;
					}
					switch( cur.value ) {
					case Code(expr):
						eargs.push({ expr : ECheckType(expr,a.type), pos : expr.pos });
					case RawValue(v):
						error("TODO", cur.pmin, cur.pmax);
					}
				}
			}

			var access = APrivate;
			for( a in m.attributes )
				if( a.name == "public" && a.value.match(RawValue("true")) ) {
					m.attributes.remove(a);
					access = APublic;
					break;
				}

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
						if( eset != null || mc.parent == null ) break;
						mc = cast(mc.parent, MetaComponent);
					}
					aexprs.push(macro var attrib = $e);
					aexprs.push({ expr : EMeta({ pos : e.pos, name : ":privateAccess" }, { expr : ECall(eset,[macro cast tmp.obj,macro attrib]), pos : e.pos }), pos : e.pos });
					aexprs.push(macro @:privateAccess tmp.initStyle($v{p.name},attrib));
				}
			}
			var attributes = avalues.length == 0 ? macro null : { expr : EObjectDecl([for( m in avalues ) { field : m.attr, expr : { expr : EConst(CString(m.value)), pos : pos } }]), pos : pos };
			var ct = comp.baseType;
			var exprs : Array<Expr> = if( isRoot ) {
				var baseCheck = { expr : ECheckType(macro this,ct), pos : Context.currentPos() };
				[
					(macro var tmp : domkit.Properties<$componentsType> = this.dom),
					macro if( tmp == null ) {
						tmp = domkit.Properties.create($v{name},($baseCheck:$componentsType), $attributes);
						this.dom = tmp;
					} else {
						@:privateAccess tmp.component = cast domkit.Component.get($v{name});
						tmp.initAttributes($attributes);
					},
				];
			} else
				[macro var tmp = @:privateAccess domkit.Properties.createNew($v{name},tmp, [$a{eargs}], $attributes)];
			for( a in m.attributes.copy() )
				if( a.name == "id" ) {
					var field = switch( a.value ) {
					case RawValue(v): v;
					default: continue;
					}
					var isArray = StringTools.endsWith(field,"[]");
					if( isArray ) {
						switch( attributes.expr ) {
						case EObjectDecl(fields):
							for( f in fields )
								if( f.field == "id" ) {
									fields.remove(f);
									break;
								}
						default:
						}
						field = field.substr(0,field.length-2);
						exprs.push(macro this.$field.push(cast tmp.obj));
						if( !data.declaredIds.exists(field) ) {
							data.declaredIds.set(field, true);
							data.fields.push({
								name : field,
								access : [access],
								pos : makePos(pos, a.pmin, a.pmax),
								kind : FVar(TPath({ pack : [], name : "Array", params : [TPType(ct)] }), macro []),
							});
						}
					} else {
						exprs.push(macro this.$field = cast tmp.obj);
						data.fields.push({
							name : field,
							access : [access],
							pos : makePos(pos, a.pmin, a.pmax),
							kind : FVar(ct),
						});
					}
				}
			for( e in aexprs )
				exprs.push(e);
			for( c in m.children ) {
				var e = buildComponentsInit(c, data, pos);
				if( e != null ) exprs.push(e);
			}
			return macro $b{exprs};
		case Text(text):
			var c = loadComponent("text",m.pmin, m.pmax);
			return macro {
				var tmp = @:privateAccess domkit.Properties.createNew("text",tmp,[]);
				tmp.setAttribute("text",VString($v{text}));
			};
		case CodeBlock(expr):
			var expr = Context.parseInlineString(expr,makePos(pos, m.pmin, m.pmax));
			switch( expr.expr ) {
			case EConst(CIdent(v)):
				return macro domkit.Element.create("object",null,tmp,$i{v});
			default:
				replaceLoop(expr, function(m) return buildComponentsInit(m, data, pos));
			}
			return expr;
		case Macro(id):
			var args = m.arguments == null ? null : [for( a in m.arguments ) switch( a.value ) {
				case RawValue(v): { expr : EConst(CString(v)), pos : makePos(pos, a.pmin, a.pmax) };
				case Code(e): e;
			}];
			var m = processMacro(id, args, makePos(pos, m.pmin, m.pmax));
			if( m == null ) error("Unsupported custom text", m.pmin, m.pmax);
			return buildComponentsInit(m, data, pos);
		}
	}

	static function replaceLoop( e : Expr, callb : MarkupParser.Markup -> Expr ) {
		switch( e.expr ) {
		case EMeta({ name : ":markup" },{ expr : EConst(CString(str)), pos : pos }):
			var p = new MarkupParser();
			var pinf = Context.getPosInfos(pos);
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

	static function buildDocument( cl : haxe.macro.Type.ClassType, str : String, pos : Position, fields : Array<Field>, rootName : String ) {
		var p = new MarkupParser();
		var pinf = Context.getPosInfos(pos);
		var root = p.parse(str,pinf.file,pinf.min).children[0];

		if( rootName != null )
			switch( root.kind ) {
			case Node(n): if( n != rootName ) Context.error("Root element shoud be "+rootName, pos);
			default: throw "assert";
			}

		var initExpr = buildComponentsInit(root, { fields : fields, declaredIds : new Map() }, pos, true);
		var csup = cl.superClass;
		var isFirst = true;
		while( csup != null ) {
			var cl = csup.t.get();
			if( cl.findField("document") != null ) {
				isFirst = false;
				break;
			}
			csup = cl.superClass;
		}

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
	}

	public static function buildObject() {
		var pre = preload;
		if( pre.length > 0 ) {
			preload = [];
			while( pre.length > 0 ) {
				var p = pre.shift();
				switch( Context.getType(p) ) {
				case TInst(c,_): c.get(); // force build
				default:
				}
			}
		}

		var cl = Context.getLocalClass().get();
		var fields = Context.getBuildFields();
		var hasDocument = null;
		var hasMeta = null;
		for( f in fields ) {
			if( f.name == "SRC" ) {
				switch( f.kind ) {
				case FVar(_,{ expr : EMeta({ name : ":markup" },{ expr : EConst(CString(str)) }), pos : pos }):
					hasDocument = { f : f, str : str, pos : pos };
				default:
				}
			}
			if( hasMeta == null )
				for( m in f.meta )
					if( m.name == ":p" )
						hasMeta = m.pos;
		}

		var isComp = cl.meta.has(":uiComp");
		var foundComp = null;
		if( isComp ) {
			try {
				var m = new MetaComponent(Context.getLocalType(), fields);
				m.hasDocument = hasDocument != null;
				if( componentsType == null ) componentsType = m.baseType;
				Context.defineType(m.buildRuntimeComponent(componentsType,fields));
				var t = m.getRuntimeComponentType();
				fields.push((macro class {
					static var ref : $t = null;
				}).fields[0]);
				COMPONENTS.set(m.name, m);
				foundComp = m.name;
				RESOLVED_COMPONENTS.set(m.name,{ path : null, c : m }); // allow self resolution in document build
			} catch( e : MetaComponent.MetaError ) {
				Context.error(e.message, e.position);
			}
		} else if( hasMeta != null )
			Context.error("@:p not allowed without @:uiComp", hasMeta);

		if( hasDocument != null ) {
			try {
				buildDocument(cl, hasDocument.str, hasDocument.pos, fields, foundComp);
			} catch( e : Error ) {
				Context.error(e.message, makePos(hasDocument.pos,e.pmin,e.pmax));
			}
			fields.remove(hasDocument.f);
		}
		if( foundComp != null )
			RESOLVED_COMPONENTS.remove(foundComp);
		return fields;
	}

	static function error( msg : String, pmin : Int, pmax : Int = -1 ) : Dynamic {
		throw new Error(msg, pmin, pmax);
	}

	static function makePos( p : Position, pmin : Int, pmax : Int ) {
		var p0 = Context.getPosInfos(p);
		return Context.makePosition({ min : pmin, max : pmax, file : p0.file });
	}

	#end

}
