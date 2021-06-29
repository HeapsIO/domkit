package domkit;
#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import domkit.Error;

using haxe.macro.Tools;
using haxe.macro.ExprTools;

typedef ComponentData = {
	var declaredIds : Map<String,Bool>;
	var fields : Array<haxe.macro.Expr.Field>;
	var inits : Array<Expr>;
	var hasContent : Bool;
}

#end

class Macros {
	#if macro

	@:persistent static var COMPONENTS = new Map<String, domkit.MetaComponent>();
	@:persistent static var componentsSearchPath : Array<String> = ["h2d.domkit.BaseComponents.$Comp"];
	@:persistent static var componentsType : ComplexType;
	@:persistent static var preload : Array<String> = [];
	@:persistent public static var defaultParserPath : String = null;
	static var RESOLVED_COMPONENTS = new Map();

	public static dynamic function processMacro( id : String, args : Null<Array<haxe.macro.Expr>>, pos : haxe.macro.Expr.Position ) : MarkupParser.Markup {
		return null;
	}

	public static function registerComponentsPath( path : String ) {
		if( componentsSearchPath.indexOf(path) < 0 )
			componentsSearchPath.push(path);
	}

	public static function setDefaultParser( path : String ) {
		defaultParserPath = path;
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
			case TInst(c,_):
				if( p == "$" ) path = c.toString(); // if we found with unqualified name, requalify
				c.get(); // force build
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

	static function replaceThis( e : haxe.macro.Expr, ethis : haxe.macro.Expr ) {
		switch( e.expr ) {
		case EConst(CIdent("__this__")):
			e.expr = ethis.expr;
		default:
			e.iter(function(e) replaceThis(e,ethis));
		}
	}

	static function remapBind( rootExpr : haxe.macro.Expr ) {
		var isBound = false;
		var bname:String = null;
		function _remap(e : haxe.macro.Expr) {
			switch( e.expr ) {
				case EMeta(m, group) if( m.name == "bind" ):
					if(m.params.length > 0)
						switch(m.params[0].expr) {
							case EConst(CIdent(name)):
								bname = name;
							default:
						}
					isBound = true;
					_remap(group);
					e.expr = group.expr;
					return;
				case EConst(CIdent(name)) if(isBound):
					e.expr = ((macro domkit.Macros.bindVar($i{name})).expr); 
					return;
				case EField(obj, name) if(isBound):
					e.expr = ((macro domkit.Macros.bindVar($obj.$name)).expr); 
					return;
				default:
			}
			e.iter(_remap);
		}
		_remap(rootExpr);
		return {
			isBound: isBound,
			name: bname
		};
	}
	
	static var latestBlock : Array<Expr> = null;

	static function remapBuild( e : haxe.macro.Expr) {
		switch( e.expr ) {
		case EMeta(m, expr) if( m.name == "rebuild" ):
			switch( expr.expr ) {
			case EVars([v]):
				var value = v.expr;
				v.expr = null;
				if( latestBlock == null ) throw "assert";
				latestBlock.push(expr);
				if( value != null ) {
					e.expr = ECall({ expr : EConst(CIdent("registerCheckRebuild")), pos : e.pos },[{ expr : EFunction(null,{
						args : [],
						ret : null,
						expr : { expr : EBlock([
							{ expr : EBinop(OpAssign,{ expr : EConst(CIdent(v.name)), pos : e.pos },value), pos : e.pos },
							macro return null,
						]), pos : e.pos },
					}), pos : e.pos }]);
				}
			default:
				e.expr = ECall({ expr : EConst(CIdent("registerCheckRebuild")), pos : e.pos },[{ expr : EFunction(null,{
					args : [],
					ret : null,
					expr : { expr : EReturn(expr), pos : e.pos },
				}), pos : e.pos }]);
			}
		case EBinop(op = OpEq | OpNotEq, { expr : EMeta(m = { name : "rebuild" },e1) }, e2):
			e.expr = EMeta(m,{ expr : EBinop(op,e1,e2), pos : e.pos });
			remapBuild(e);
			return;
		case EBlock(exprs):
			var prev = latestBlock;
			latestBlock = [];
			for( e in exprs ) {
				remapBuild(e);
				latestBlock.push(e);
			}
			e.expr = EBlock(latestBlock);
			latestBlock = prev;
			return;
		default:
		}
		e.iter(remapBuild);
	}

	static function withPos( e : haxe.macro.Expr, pos : Position ) : haxe.macro.Expr {
		e = e.map(function(e) return withPos(e,pos));
		return { expr : e.expr, pos : pos };
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
				if( m.condition != null )
					error("Cannot have a condition on root element", m.condition.pmin, m.condition.pmax);
				if( m.arguments.length > 0 )
					error("Arguments should be passed in super constructor", m.pmin, m.pmax);
			} else {
				if( args == null )
					error('Component $name is a @:uiRootComponent and is not constructible', m.pmin, m.pmax);
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
					var expr = switch( cur.value ) {
					case Code(expr): expr;
					case RawValue(v): { expr : EConst(CString(v)), pos : makePos(pos,cur.pmin,cur.pmax) };
					};
					eargs.push({ expr : ECheckType(expr,a.type), pos : expr.pos });
				}
			}

			var access = APrivate;
			for( a in m.attributes ) {
				switch( a.name ) {
				case "public" if( a.value.match(RawValue("true")) ):
					m.attributes.remove(a);
					access = APublic;
				case "id" if( a.value.match(RawValue("true")) ):
					var name = null;
					for( a in m.attributes )
						if( a.name == "class" ) {
							switch( a.value ) {
							case RawValue(v): name = v.split(" ")[0];
							default:
							}
						}
					if( name == null ) error("Could not tell name from class attribute", a.pmin, a.pmax);
					a.value = RawValue(name);
				default:
				}
			}

			var avalues = [];
			var aexprs = [];
			var isContent = false;
			for( attr in m.attributes ) {
				if( attr.name == "__content__" ) {
					isContent = true;
					continue;
				}
				var p = Property.get(attr.name, false);
				var h = p == null ? null : comp.getHandler(p);
				if( h == null ) {
					switch( attr.value ) {
					case Code(e):
						var field = attr.name;
						var fpos = makePos(e.pos, attr.pmin, attr.pmin + attr.name.length);
						var expr = { expr : EBinop(OpAssign,{ expr : EField(macro __this__,field), pos : fpos },e), pos : fpos };
						aexprs.push(expr);
					default:
						if( p == null )
							error("Unknown property "+attr.name, attr.pmin, attr.pmin + attr.name.length);
						else
							error("Component "+comp.name+" does not handle property "+p.name, attr.pmin, attr.pmin + attr.name.length);
					}
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
					var mc = Std.downcast(comp, MetaComponent);
					var eset = null;
					while( mc != null ) {
						eset = mc.setExprs.get(p.name);
						if( eset != null || mc.parent == null ) break;
						mc = cast(mc.parent, MetaComponent);
					}
					if( eset == null ) {
						if( p.name == "class" ) {
							aexprs.push(macro tmp.setClasses($e));
						} else
							error("Unknown property "+comp.name+"."+p.name, attr.vmin, attr.pmax);
					} else {
						var binding = remapBind(e);
						var eattrib = { expr : EConst(CIdent("__attrib")), pos : e.pos };
						var setter = { expr : ECall(withPos(eset,e.pos),[macro cast tmp.obj,eattrib]), pos : e.pos };
						aexprs.push(macro {
							function __onVarChanged() {
								var __attrib = $e;
								@:privateAccess $setter;
								@:privateAccess tmp.initStyle($v{p.name},$eattrib);
							}
							$e{
								if(binding.isBound)
									macro registerBind(__onVarChanged, $v{binding.name})
								else macro {}
							}
							__onVarChanged();
						});
					}
				}
			}
			var attributes = avalues.length == 0 ? macro null : { expr : EObjectDecl([for( m in avalues ) { field : m.attr, expr : { expr : EConst(CString(m.value)), pos : pos } }]), pos : pos };
			var ct = comp.baseType;
			var exprs : Array<Expr> = if( isRoot ) {
				var baseCheck = { expr : ECheckType(macro this,ct), pos : Context.currentPos() };
				var initAttr = attributes.expr.match(EConst(CIdent("null"))) ? macro null : macro tmp.initAttributes($attributes);
				[
					(macro var tmp : domkit.Properties<$componentsType> = this.dom),
					macro @:pos(pos) if( tmp == null ) {
						tmp = domkit.Properties.create($v{name},($baseCheck:$componentsType), $attributes);
						this.dom = tmp;
					} else {
						@:privateAccess tmp.component = cast domkit.Component.get($v{name});
						$initAttr;
					},
				];
			} else {
				var newExpr = macro @:pos(pos) domkit.Properties.createNew($v{name},tmp, [$a{eargs}], $attributes);
				[macro var tmp = @:privateAccess $newExpr];
			}
			if( isContent ) {
				exprs.push(macro __contentRoot = tmp);
				data.hasContent = true;
			}
			for( a in m.attributes.copy() )
				if( a.name == "id" ) {
					var field = switch( a.value ) {
					case RawValue(v): MetaComponent.componentNameToClass(v,true);
					default: continue;
					}
					var isArray = StringTools.endsWith(field,"[]");
					if( isArray ) {
						field = field.substr(0,field.length-2);
						switch( attributes.expr ) {
						case EObjectDecl(fields):
							for( f in fields )
								if( f.field == "id" ) {
									f.expr.expr = EConst(CString(field));
									break;
								}
						default:
						}
						exprs.push(macro this.$field.push(cast tmp.obj));
						if( !data.declaredIds.exists(field) ) {
							data.declaredIds.set(field, true);
							data.fields.push({
								name : field,
								access : [access],
								pos : makePos(pos, a.pmin, a.pmax),
								kind : FVar(TPath({ pack : [], name : "Array", params : [TPType(ct)] }), null),
							});
							data.inits.push(macro this.$field = []);
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
			if( isRoot && data.hasContent ) {
				exprs.unshift(macro var __contentRoot);
				exprs.push(macro @:privateAccess dom.contentRoot = __contentRoot.contentRoot);
			}

			var ct = Std.downcast(comp, MetaComponent).baseType;
			var ethis = isRoot ? macro this : macro (cast tmp.obj : $ct);
			for( e in exprs )
				replaceThis(e, ethis);

			if( m.condition != null ) {
				remapBuild(m.condition.cond);
				return macro if( ${m.condition.cond} ) $b{exprs};
			}
			return macro $b{exprs};
		case Text(text):
			var c = loadComponent("text",m.pmin, m.pmax);
			return macro {
				var tmp = @:privateAccess domkit.Properties.createNew("text",tmp,[]);
				tmp.setAttribute("text",VString($v{text}));
			};
		case CodeBlock(expr):
			var offset = 0;
			var sexpr = StringTools.trim(expr);
			var lchar = sexpr.charCodeAt(sexpr.length - 1);
			if( lchar == ";".code || lchar == '}'.code ) {
				offset = -1;
				expr = "{"+expr+"}";
			}
			var expr = Context.parseInlineString(expr,makePos(pos, m.pmin + offset, m.pmax));
			replaceLoop(expr, function(m) return buildComponentsInit(m, data, pos));
			remapBuild(expr);
			return expr;
		case For(expr):
			var expr = Context.parseInlineString(expr,makePos(pos, m.pmin, m.pmax));
			remapBuild(expr);
			expr = switch( expr.expr ) {
			case EParenthesis(e): e;
			default: expr;
			}
			var exprs = [for( c in m.children ) buildComponentsInit(c, data, pos)];
			return macro for( $expr ) $a{exprs};
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
			case Node(n): if( n != rootName ) Context.error("Root element should be "+rootName, pos);
			default: throw "assert";
			}

		var inits = [];
		var initExpr = buildComponentsInit(root, { fields : fields, declaredIds : new Map(), inits : inits, hasContent : false }, pos, true);
		if( inits.length > 0 ) {
			inits.push({ expr : initExpr.expr, pos : initExpr.pos });
			initExpr.expr = EBlock(inits);
		}
		var initFunc = "new";
		var initArgs = null;

		var ccur = cl;
		while( true ) {
			if( ccur.meta.has(":uiInitFunction") || (initArgs == null && ccur.meta.has(":domkitInitArgs")) ) {
				for( m in ccur.meta.get() )
					switch( m.name ) {
					case ":uiInitFunction" if( m.params.length == 1 ):
						switch( m.params[0].expr ) {
						case EConst(CIdent(name)): initFunc = name;
						default: Context.warning("Invalid @:uiInitFunction(funName)", m.pos);
						}
					case ":domkitInitArgs" if( initArgs == null && ccur != cl ):
						switch( m.params[0].expr ) {
						case ECheckType({ expr : EConst(CIdent(name)) }, TAnonymous(fields))
						   | EParenthesis({ expr : ECheckType({ expr : EConst(CIdent(name)) }, TAnonymous(fields)) }):
						   if( name == initFunc ) initArgs = fields;
						default: throw "assert";
						}
					default:
					}
			}
			if( ccur.superClass == null ) break;
			ccur = ccur.superClass.t.get();
		}

		var found = null;
		for( f in fields )
			if( f.name == initFunc ) {
				switch( f.kind ) {
				case FFun(f):
					function replace( e : Expr ) {
						switch( e.expr ) {
						case ECall({ expr : EConst(CIdent("initComponent")) },[]):
							// we don't generate an override initComponent method
							// because it needs to access constructor variables - so we directly inline it
							e.expr = initExpr.expr;
							found = e.pos;
						default: haxe.macro.ExprTools.iter(e, replace);
						}
					}
					replace(f.expr);
					var ct : ComplexType = TAnonymous([for( a in f.args ) {
						name : a.name,
						kind : FVar(a.type,a.value),
						pos : cl.pos,
						meta : a.opt ? [{name:":optional",pos:cl.pos}] : null }
					]);
					cl.meta.add(":domkitInitArgs",[macro ($i{initFunc} : $ct)],cl.pos);
					if( found == null )
						Context.error("Missing initComponent() call", f.expr.pos);
					break;
				default:
				}
			}
		if( found != null )
			return;
		if( initArgs == null ) {
			if( initFunc == "new" )
				initArgs = [{ name : "parent", kind : FVar(componentsType), meta :  [{name:":optional",pos:cl.pos}], pos : cl.pos }];
			else {
				Context.error("Missing function "+initFunc, Context.currentPos());
				return;
			}
		}
		var anames = [for( a in initArgs ) macro $i{a.name}];
		fields.push({
			name : initFunc,
			pos : cl.pos,
			kind : FFun({
				ret : null,
				args : [for( a in initArgs) {
					name : a.name,
					type : switch( a.kind ) { case FVar(t,_): t; default: throw "assert"; },
					value : switch( a.kind ) { case FVar(_,e): e; default: throw "assert"; },
					opt : a.meta.length == 1,
				}],
				expr : if( initFunc == "new" ) macro { super($a{anames}); $initExpr; } else macro { super.$initFunc($a{anames}); $initExpr; },
			}),
			access: [initFunc == "new" ? APublic : AOverride],
		});
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

		var isComp = !cl.meta.has(":uiNoComponent");
		var foundComp = null;
		if( isComp ) {
			try {
				var m = new MetaComponent(Context.getLocalType(), fields);
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
			Context.error("@:p not allowed with @:uiNoComponent", hasMeta);

		if( hasDocument != null ) {
			try {
				buildDocument(cl, hasDocument.str, hasDocument.pos, fields, foundComp);
			} catch( e : Error ) {
				Context.error(e.message, makePos(hasDocument.pos,e.pmin,e.pmax));
			}
			fields.remove(hasDocument.f);
		} else if( isComp && !cl.meta.has(":domkitDecl") ) {
			buildDocument(cl, '<$foundComp></$foundComp>', cl.pos, fields, foundComp);
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

	public static macro function bindVar(e : haxe.macro.Expr) : haxe.macro.Expr {
		switch(Context.typeof(e)) {
			case TInst(_):
				return e;
			case TFun(args,ret):
				if(args.length == 1) {
					function matchCallback(t:Type) {
						return switch(t) {
							// Void->Void callback
							case TFun([], TAbstract(_.get() => {module: "StdTypes", name: "Void"}, [])):
								return macro {
									$e(__onVarChanged);
								};
							// (newValue:T)->Void callback
							case TFun([{ t : argType }], TAbstract(_.get() => {module: "StdTypes", name: "Void"}, [])) if (Context.unify(argType,ret)):
								return macro {
									$e(v -> __onVarChanged());
								};
							// (newValue:T, oldValue:T)->Void callback
							case TFun([{ t : argType }, { t : arg2Type }], TAbstract(_.get() => {module: "StdTypes", name: "Void"}, [])) if (Context.unify(argType,ret) && Context.unify(arg2Type,ret)):
								return macro {
									$e((v1,v2) -> __onVarChanged());
								};
							default: null;
						}
					}
					var t = args[0].t;
					var expr = switch(t) {
						case TAbstract(_,[func]):
							matchCallback(func);
						default:
							matchCallback(t);
					};
					if(expr != null)
						return expr;
				}
			default:
		}
		throw "Unsupported callback type used with @bind";
	}

}
