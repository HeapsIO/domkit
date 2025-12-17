package domkit;
import haxe.macro.Type;
import haxe.macro.Expr;
using haxe.macro.Tools;

class MetaError {
	public var message : String;
	public var position : Position;
	public function new(msg,pos) {
		this.message = msg;
		this.position = pos;
	}
}

enum ParserMode {
	PNone;
	PAuto;
	PCustom;
}

class MetaComponent extends Component<Dynamic,Dynamic> {

	#if macro
	public var baseType : ComplexType;
	public var parserType : ComplexType;
	public var setExprs : Map<String, Expr> = new Map();
	public var typePath : String;
	public var isGlobal : Bool;
	var parser : CssValue.ValueParser;
	var classType : ClassType;
	var baseClass : ClassType;
	var constructorPath : Array<String>;
	var constructorArgs : Array<{ type : ComplexType, name : String, opt : Bool }>;
	var parserDependencies : Map<String, Field> = new Map();

	public function new( t : Type, fields : Array<Field> ) {
		classType = switch( t ) {
		case TInst(c, _): c.get();
		default: error("Invalid type",haxe.macro.Context.currentPos());
		}
		typePath = makeTypePath(classType).join(".");

		var c = classType;
		var name = getCompName(c);
		if( name == null ) throw "assert";

		var ccur = c;
		var metaParent = null;
		while( true ) {
			if( ccur.superClass == null ) break;
			var csup = ccur.superClass.t.get();
			var cname = getCompName(csup, true);
			if( cname != null ) {
				metaParent = @:privateAccess try Macros.loadComponent(cname,0,0,true) catch( e : domkit.Error ) null catch( e : Error ) null;
				if( metaParent == null ) error("Missing super component registration "+cname, c.pos);
				break;
			}
			ccur = csup;
		}
		super(name,null,metaParent);

		initParser(c);
		if( metaParent == null ) {
			addHandler("class", parser.parseArray.bind(parser.parseIdent), null, macro : String);
			addHandler("id", parser.parseId, null, macro : String);
		}

		var baseT = t;
		for( i in c.interfaces )
			if( i.t.toString() == "domkit.ComponentDecl" )
				baseT = i.params[0];
		baseClass = switch( baseT.follow() ) { case TInst(c,_): c.get(); default: throw "assert"; };
		if( baseT != t )
			baseClass.meta.add(":uiComp",[{ expr : EConst(CString(name)), pos : c.pos }], c.pos);
		baseType = baseT.toComplexType();

		// if we have a component with type parameters, let's replace them by Dynamic
		switch( baseType ) {
		case TPath(tp) if( (tp.sub ?? tp.name) == baseClass.name && tp.params != null && tp.params.length > 0 ):
			tp.params = [for( _ in tp.params ) TPType(TPath({ pack : [], name : "Dynamic"}))];
		default:
		}

		var fconstr = null;
		for( f in fields ) {
			if( f.meta != null )
				for( m in f.meta )
					if( m.name == ":p" ) {
						defineField(f, m);
						break;
					}
			if( f.name == "new" && fconstr == null )
				fconstr = f;
			if( f.name == "create" && f.access.indexOf(AStatic) >= 0 )
				fconstr = f;
		}
		var isRootComp = classType.meta.has(":uiRootComponent");
		if( !isRootComp && metaParent != null && metaParent.constructorPath == null )
			isRootComp = true;
		if( !isRootComp )
			initConstructor(fconstr);
	}

	public function getConstructorArgs() {
		if( constructorPath == null )
			return null;
		var p = this;
		while( p != null ) {
			if( p.constructorArgs != null )
				return p.constructorArgs;
			p = Std.instance(p.parent, MetaComponent);
		}
		return [];
	}

	function initConstructor( f : Field ) {
		if( f != null && f.name == "create" ) {
			var classPath = makeTypePath(classType);
			constructorPath = classPath.concat(["create"]);
		} else {
			constructorPath = switch( baseType ) {
			case TPath(p):
				var path = p.pack.copy();
				path.push(p.name);
				if( p.sub != null ) path.push(p.sub);
				path.push("new");
				path;
			default: throw "assert";
			}
		}

		if( f == null ) return;

		switch( f.kind ) {
		case FFun(f):
			var args = f.args.copy();
			args.pop(); // parent
			for( a in args ) {
				if( a.type == null && a.value != null ) {
					switch a.value.expr {
					case EConst(c):
						switch c {
						case CInt(_): a.type = TPath({ name : "Int", pack : [] });
						case CFloat(_): a.type = TPath({ name : "Float", pack : [] });
						case CString(_): a.type = TPath({ name : "String", pack : [] });
						case CIdent("true" | "false"): a.type = TPath({ name : "Bool", pack : [] });
						default:
						}
					default:
					}
				}
				if( a.type == null )
					error("Missing explicit type for constructor argument "+a.name, f.expr.pos);
			}
			constructorArgs = [for( a in args ) {
				name : a.name,
				opt : a.opt,
				type : haxe.macro.Context.resolveType(a.type, f.expr.pos).toComplexType()
			}];
		default:
			error("Create method is not a function", f.pos);
		}
	}

	function initParser( c : ClassType ) {
		var pdef = c.meta.extract(":parser")[0];
		var path = null;

		if( pdef != null ) {
			if( pdef.params.length == 0 )
				error("Invalid parser definition", pdef.pos);
			var e = pdef.params[0];
			path = [];
			while( true ) {
				switch( e.expr ) {
				case EField(e2, field):
					path.unshift(field);
					e = e2;
				case EConst(CIdent(i)):
					path.unshift(i);
					break;
				default:
					error("Invalid parser definition", e.pos);
				}
			}
		} else if( parent == null ) {
			var defPath = Macros.defaultParserPath;
			if( defPath != null ) path = defPath.split(".");
		}

		if( path == null ) {
			if( parent != null ) {
				var parent = cast(parent,MetaComponent);
				parserType = parent.parserType;
				parser = parent.parser;
			} else {
				parserType = macro : domkit.CssValue.ValueParser;
				parser = new domkit.CssValue.ValueParser();
			}
			return;
		}
		var name = path.pop();
		inline function isUpper(str:String) return str.charCodeAt(0) >= 'A'.code && str.charCodeAt(0) <= 'Z'.code;
		var subType = path.length > 0 && isUpper(path[path.length - 1]) ? path.pop() : null;
		parserType = TPath({ pack : path, name : subType == null ? name : subType, sub : subType == null ? null : name });

		var clPath = path.length == 0 ? name : path.join(".")+"."+name;
		var cl = std.Type.resolveClass(clPath);
		if( cl == null )
			error("Class "+clPath+" has not been compiled in macros", pdef == null ? haxe.macro.Context.currentPos() : pdef.pos);
		parser = std.Type.createInstance(cl,[]);
	}

	function defineField( f : Field, pm : MetadataEntry ) {
		var defExpr = null;
		var t = switch( f.kind ) {
		case FVar(t, def), FProp(_, _, t, def): defExpr = def; t;
		default: return;
		}
		if( t == null && defExpr != null )
			switch( defExpr.expr ) {
			case EConst(c):
				switch( c ) {
				case CInt(_): t = macro : Int;
				case CFloat(_): t = macro : Float;
				case CString(_): t = macro : String;
				case CIdent("true" | "false"): t = macro : Bool;
				default:
				}
			default:
			}
		if( t == null )
			error("Type required", f.pos);
		var tt = haxe.macro.Context.resolveType(t, f.pos);
		t = tt.toComplexType();

		var prop = null;
		var parserMode = PNone;

		if( pm.params.length > 0 )
			switch( pm.params[0].expr ) {
			case EConst(CIdent("none")):
				parserMode = PNone;
			case EConst(CIdent("auto")):
				parserMode = PAuto;
			case EConst(CIdent(name)):
				parserMode = PCustom;
				var fname = "parse"+componentNameToClass(name);
				var meth = Reflect.field(this.parser,fname);
				if( meth == null )
					error(parserType.toString()+" has no field "+fname, pm.params[0].pos);
				prop = {
					def : null,
					expr : macro (parser.$fname : domkit.CssValue -> $t),
					value : function(css:CssValue) : Dynamic {
						return Reflect.callMethod(this.parser,meth,[css]);
					}
				};
			default:
			}

		var trans = null;
		for( m in f.meta )
			if( m.name == ":t" && m.params.length > 0 ) {
				switch( m.params[0].expr ) {
				case EConst(CIdent(name)):
					var fname = "transition"+componentNameToClass(name);
					var meth = Reflect.field(this.parser,fname);
					if( meth == null )
						error(parserType.toString()+" has no field "+fname, m.params[0].pos);
					trans = macro (parser.$fname : $t -> $t -> Float -> $t);
				default:
				}
			}

		if( prop == null ) {
			prop = parserFromType(tt, f.pos, parserMode);
			if( prop == null ) error("Unsupported type "+t.toString()+", use custom parser", f.pos);
		} else {
			var pdef = parserFromType(tt, f.pos, parserMode);
			if( pdef != null ) prop.def = pdef.def;
		}

		switch( defExpr ) {
		case null:
		case { expr : EConst(c), pos : pos }:
			prop.def = defExpr;
		default:
			error("Invalid default expr", f.pos);
		}

		var h = addHandler(CssParser.haxeToCss(f.name), prop.value, prop.def, t);
		h.position = f.pos;
		h.fieldName = f.name;
		h.parserExpr = prop.expr;
		h.transitionExpr = trans;
	}

	public static function componentNameToClass( name : String, isField = false ) {
		return CssParser.cssToHaxe(name,isField);
	}

	public static function makeTypePath( t : BaseType ) {
		var path = t.module.split(".");
		if( t.name != path[path.length-1] ) path.push(t.name);
		return path;
	}

	function makeTypeExpr( t : BaseType, pos : Position ) {
		var path = makeTypePath(t);
		return haxe.macro.MacroStringTools.toFieldExpr(path);
	}

	function parserFromType( t : Type, pos : Position, mode : ParserMode ) : { expr : Expr, value : CssValue -> Dynamic, def : Expr } {
		switch( t ) {
		case TAbstract(a,params):
			switch( a.toString() ) {
			case "Int": return { expr : macro parser.parseInt, value : parser.parseInt, def : macro 0 };
			case "Float": return { expr : macro parser.parseFloat, value : parser.parseFloat, def : macro 0. };
			case "Bool": return { expr : macro parser.parseBool, value : parser.parseBool, def : macro false };
			case "Null":
				var p = parserFromType(params[0],pos,mode);
				if( p != null && p.def != null ) {
					switch( mode ) {
					case PNone:
						p.expr = macro parser.parseNone.bind(${p.expr});
						p.value = parser.parseNone.bind(p.value);
					case PAuto:
						p.expr = macro parser.parseAuto.bind(${p.expr});
						p.value = parser.parseAuto.bind(p.value);
					case PCustom:
					}
					p.def = null;
				}
				return p;
			default:
				var ab = a.get();
				if (ab.meta.has(":enum")) {
					var names = [];
					for (field in ab.impl.get().statics.get()) {
						if (field.meta.has(":enum") && field.meta.has(":impl")) {
							names.push(field.name);
						}
					}

					var idents = [for( n in names ) CssParser.haxeToCss(n)];
					var fallback = [for( n in names ) n.toLowerCase()];
					var enexpr = makeTypeExpr(ab, pos);

					var nameExprs = [ for (name in names) macro $enexpr.$name ];
					var fname = "parse" + ab.name;

					var parserField = parserDependencies.get(fname);
					var errMsg = idents.length > 8 ? " is not part of " + ab.name : " should be "+idents.join("|");
					if (parserField == null) {
						var invalidEnum = macro parser.invalidProp(i + $v{errMsg});
						parserField = {
							name: fname,
							pos: pos,
							kind: FFun({
								args: [ { name: "css", type: (macro : CssValue) } ],
								ret: t.toComplexType(),
								expr: macro {
									#if (haxe_ver >= 4.3) static #end var all = $a{nameExprs};
									#if (haxe_ver >= 4.3) static #end var idents = $v{idents};
									#if (haxe_ver >= 4.3) static #end var names = $v{names};
									#if (haxe_ver >= 4.3) static #end var fallback = $v{fallback};
									inline function getIndex(str: String) {
										var idx = idents.indexOf(str);
										if( idx < 0 )
											idx = names.indexOf(str);
										if( idx < 0 )
											idx = fallback.indexOf(str);
										return idx;
									}
									switch( css ) {
										case VIdent(i):
											var idx = getIndex(i);
											if( idx < 0 )
												return $invalidEnum;
											return all[idx];
										default:
											return parser.invalidProp();
									}
								},
							}),
						};
						parserDependencies.set(fname, parserField);
					}
					var p = {
						expr: (macro $i{fname}),
						value : function(css:CssValue) {
							return switch( css ) {
								case VIdent(i) if( idents.indexOf(i) >= 0 || fallback.indexOf(i) >= 0 ): true;
								case VIdent(v): parser.invalidProp(v + errMsg);
								default: parser.invalidProp();
							}
						},
						def : null,
					};
					switch( mode ) {
					case PNone:
						p.expr = macro parser.parseNone.bind(${p.expr});
						p.value = parser.parseNone.bind(p.value);
					case PAuto:
						p.expr = macro parser.parseAuto.bind(${p.expr});
						p.value = parser.parseAuto.bind(p.value);
					case PCustom:
					}
					return p;
				}
			}
		case TInst(c,_):
			switch( c.toString() ) {
			case "String":
				return  { expr : macro parser.parseString, value : parser.parseString, def : null };
			default:
			}
		case TEnum(en, params):
			var enumType = en.get();
			var idents = [for( n in enumType.names ) CssParser.haxeToCss(n)];
			var fallback = [for( n in enumType.names ) n.toLowerCase()];
			var enexpr = makeTypeExpr(enumType, pos);

			if (mode == PCustom) {
				return {
					expr : macro parser.makeEnumParser($enexpr),
					value : function(css:CssValue) {
						return switch( css ) {
						case VIdent(i) if( idents.indexOf(i) >= 0 || fallback.indexOf(i) >= 0 ): true;
						case VIdent(v): parser.invalidProp(v+" should be "+idents.join("|"));
						default: parser.invalidProp();
						}
					},
					def : null,
				};
			}
			var fname = "parse" + enumType.name;
			var ret = {
				expr: (macro $i{fname}),
				value : function(css:CssValue) {
					return switch( css ) {
					case VIdent(i), VCall(i, _) if( idents.indexOf(i) >= 0 || fallback.indexOf(i) >= 0 ): true;
					case VIdent(v), VCall(v, _): parser.invalidProp(v+" should be "+idents.join("|"));
					default: parser.invalidProp();
					}
				},
				def : null,
			};
			var parserField = parserDependencies.get(fname);
			if (parserField != null) {
				return ret;
			}
			parserField = {
				name: fname,
				pos: pos,
				kind: FFun({
					args: [ { name: "css", type: (macro : CssValue) } ],
					expr: macro {},
				}),
			};
			parserDependencies.set(fname, parserField);


			var withParam: Array<String> = [];
			var withoutParam: Array<String> = [];
			var paramCases: Array<Case> = [];
			for( nameIndex in 0...enumType.names.length ) {
				var n = enumType.names[nameIndex];
				var constr = enumType.constructs.get(n);
				switch (constr.type) {
					case TFun(args, _):
						withParam.push(n);
						var lastRequired = -1;
						for( i in 0...args.length ) {
							if( !args[i].opt )
								lastRequired = i;
						}
						if( lastRequired < 0 )
							withoutParam.push(n);

						var parsers = [];
						for (i in 0...args.length) {
							var a = args[i];
							var parser = parserFromType(a.t, pos, mode);
							parsers.push(macro {
								if (callArgs.length > $v{i}) {
									var arg = callArgs[$v{i}];
									enumArgs.push(${parser.expr}(arg));
								}
							});
						}
						var paramExpr = macro {
							if (callArgs.length < $v{lastRequired + 1})
								return parser.invalidProp(i+" requires at least "+$v{lastRequired + 1}+" parameters");
							var enumArgs: Array<Dynamic> = [];
							$b{parsers}
							return $enexpr.createByIndex($v{nameIndex}, enumArgs);
						};
						paramCases.push({
							values: [macro $v{n}],
							expr: paramExpr,
						});
					default:
						withoutParam.push(n);
				}
			}
			var invalidEnum = macro parser.invalidProp(i+" should be "+idents.join("|"));
			var paramSwitch = {pos: pos, expr: ESwitch(macro named, paramCases, macro return $invalidEnum)};

			parserField.kind = FFun({
				args: [ { name: "css", type: (macro : CssValue) } ],
				expr: macro {
					#if (haxe_ver >= 4.3) static #end var withParam = $v{withParam};
					#if (haxe_ver >= 4.3) static #end var withoutParam = $v{withoutParam};
					#if (haxe_ver >= 4.3) static #end var all = $v{enumType.names};
					#if (haxe_ver >= 4.3) static #end var idents = $v{idents};
					#if (haxe_ver >= 4.3) static #end var fallback = $v{fallback};
					inline function getIndex(str: String) {
						var idx = idents.indexOf(str);
						if( idx < 0 )
							idx = fallback.indexOf(str);
						return idx;
					}
					switch( css ) {
						case VIdent(i):
							var idx = getIndex(i);
							if( idx < 0 )
								return $invalidEnum;
							var named = all[idx];
							if( withoutParam.contains(named) )
								return $enexpr.createByIndex(idx);
							return parser.invalidProp(i+" requires parameters");
						case VCall(i, callArgs):
							var idx = getIndex(i);
							if( idx < 0 )
								return $invalidEnum;
							var named = all[idx];
							if( !withParam.contains(named) )
								return parser.invalidProp(i+" requires no parameters");

							$paramSwitch;
						default:
							return parser.invalidProp();
					}
				},
			});

			return ret;
		case TType(_):
			return parserFromType(t.follow(true), pos, mode);
		default:
		}
		return null;
	}

	function getCompName( c : ClassType, opt = false ) {
		var name = c.meta.extract(":uiComp")[0];
		var ret = null;
		if( name == null ) {
			var noComp = c.meta.has(":uiNoComponent") || (opt && c.pack[0] == "h2d");
			if (!noComp)
				ret = CssParser.haxeToCss(c.name);
		} else {
			if( name.params.length == 0 ) error("Invalid :uiComp", name.pos);
			ret = switch( name.params[0].expr ) {
				case EConst(CString(name)): name;
				default: error("Invalid :uiComp", name.pos);
			}
		}
		return ret;
	}

	function error( msg : String, pos : Position ) : Dynamic {
		throw new MetaError(msg, pos);
	}

	static function runtimeName( name : String ) {
		return "Comp"+componentNameToClass(name);
	}

	static function setPosRec( e : haxe.macro.Expr, p : Position ) {
		e.pos = p;
		haxe.macro.ExprTools.iter(e, function(e) setPosRec(e,p));
	}

	public function getModulePath() {
		return classType.module;
	}

	public function buildRuntimeComponent( componentsType, fields : Array<Field> ) {
		var cname = runtimeName(name);
		var parentExpr;
		if( parent == null )
			parentExpr = macro null;
		else {
			var parentName = runtimeName(parent.name);
			parentExpr = macro @:privateAccess domkit.$parentName.inst;
		}

		var path;
		var setters = new Map();
		for( f in fields ) {
			if( f.access.indexOf(AStatic) < 0 || !f.kind.match(FFun(_)) )
				continue;
			if( StringTools.startsWith(f.name,"set_") )
				setters.set(CssParser.haxeToCss(f.name.substr(4)), true);
		}

		var classPath = makeTypePath(classType);
		var newExpr;
		var cargs = getConstructorArgs();
		if( cargs != null ) {
			newExpr = haxe.macro.MacroStringTools.toFieldExpr(constructorPath, classType.pos);
			if( cargs.length == 0 )
				newExpr = macro function(_,parent) return ($newExpr)(parent);
			else {
				var eargs = [];
				for( i in 0...cargs.length )
					eargs.push(macro args[$v{i}]);
				eargs.push(macro parent);
				newExpr = macro function(args,parent) return ($newExpr)($a{eargs});
			}
			setPosRec(newExpr, classType.pos);
		} else
			newExpr = macro function(args,parent) throw $v{cname+" cannot be constructed"};

		var handlers = [];
		for( i in 0...propsHandler.length ) {
			var h = propsHandler[i];
			if( h == null || h.position == null ) continue;
			var p = @:privateAccess Property.ALL[i];
			if( parent != null && parent.propsHandler[i] == h && !setters.exists(p.name) ) continue;
			var ptype = h.type;
			var fname = h.fieldName;
			var set = setters.exists(p.name) ? haxe.macro.MacroStringTools.toFieldExpr(classPath.concat(["set_"+fname])) : macro function(o:$baseType,v:$ptype) o.$fname = v;
			var def = h.defaultValue == null ? macro null : h.defaultValue;
			var transExpr = h.transitionExpr == null ? macro null : macro @:privateAccess ${h.transitionExpr};
			var expr = macro addHandler($v{p.name},@:privateAccess ${h.parserExpr},($def : $ptype),@:privateAccess $set,$transExpr);
			setPosRec(expr,h.position);
			setExprs.set(p.name, set);
			handlers.push(expr);
		}

		var parserClass = switch( parserType ) {
		case TPath(t): t;
		default: throw "assert";
		}
		var forceInit = parent == null || parserType != cast(parent,MetaComponent).parserType;
		var initParser = if( forceInit ) macro parser = new $parserClass() else macro parser = @:privateAccess $parentExpr.parser;
		var fields = (macro class {
			var parser : $parserType;
			function new() {
				super($v{this.name},@:privateAccess $newExpr,$parentExpr);
				classValue = ${makeTypeExpr(classType,classType.pos)};
				$initParser;
				$b{handlers};
			}
			@:keep static var inst = new domkit.$cname();
		}).fields;

		for (n => f in parserDependencies) {
			fields.push(f);
		}

		var td : TypeDefinition = {
			pos : classType.pos,
			pack : ["domkit"],
			name : cname,
			kind : TDClass({ pack : ["domkit"], name : "Component", params : [TPType(componentsType),TPType(baseType)] }),
			fields : fields,
		};
		return td;
	}

	public function getRuntimeComponentType() {
		var name = runtimeName(name);
		return macro : domkit.$name;
	}

	public function isRuntimeComponentAlive() {
		var ct = getRuntimeComponentType();
		var pos = haxe.macro.Context.currentPos();
		return try haxe.macro.Context.resolveType(ct, pos) != null catch(_) false;
	}

	#end
}
