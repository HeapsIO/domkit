package domkit;
import domkit.Property;

class PropertyHandler<O,P> {

	public var parser(default,null) : CssValue -> P;
	#if !macro
	public var defaultValue(default,null) : P;
	public var apply(default,null) : O -> P -> Void;
	public var transition(default,null) : P -> P -> Float -> P;
	#end

	#if macro
	public var defaultValue : haxe.macro.Expr;
	public var type : haxe.macro.Expr.ComplexType;
	public var position : haxe.macro.Expr.Position;
	public var parserExpr : haxe.macro.Expr;
	public var transitionExpr : haxe.macro.Expr;
	public var fieldName : String;
	#end

	public function new(parser,def,applyType) {
		this.parser = parser;
		this.defaultValue = def;
		#if macro
		this.type = applyType;
		#else
		this.apply = applyType;
		#end
	}
}

interface ComponentDecl<T> {
}

class Component<BaseT,T> {

	public var id = -1;
	public var name : String;
	public var make : Array<Dynamic> -> BaseT -> T;
	public var parent : Component<BaseT,Dynamic>;
	var propsHandler : Array<PropertyHandler<T,Dynamic>>;

	public function new(name, make, parent) {
		this.name = name;
		this.make = make;
		this.parent = parent;
		propsHandler = parent == null ? [] : cast parent.propsHandler;
		COMPONENTS.set(name, this);
	}

	public inline function getHandler<P>( p : Property ) : PropertyHandler<T,P> {
		return cast propsHandler[p.id];
	}

	public function isOfType( c : Component<BaseT,T> ) {
		var me = this;
		do {
			if( me == c ) return true;
			me = cast me.parent;
			if( me == null ) return false;
		} while( true );
	}

	function addHandler<P>( p : String, parser : CssValue -> P, def : #if macro haxe.macro.Expr #else P #end, applyType : #if macro haxe.macro.Expr.ComplexType #else T -> P -> Void, ?transition #end ) {
		var ph = new PropertyHandler(parser,def,applyType);
		if( parent != null && propsHandler == cast parent.propsHandler ) propsHandler = propsHandler.copy();
		#if !macro
		@:privateAccess ph.transition = transition;
		#end
		propsHandler[Property.get(p).id] = ph;
		return ph;
	}

	public static function get( name : String, opt = false ) {
		var c = COMPONENTS.get(name);
		if( c == null && !opt ) throw "Unknown component "+name;
		return c;
	}

	public static macro function build( expr ) {
		switch( expr.expr ) {
		case EMeta({ name : ":markup" },{ expr : EConst(CString(str)) }):

			try {
				var p = new MarkupParser();
				var pinf = haxe.macro.Context.getPosInfos(expr.pos);
				var root = p.parse(str,pinf.file,pinf.min).children[0];

				var comp = switch( root.kind ) {
				case Node(name): @:privateAccess Macros.loadComponent(name, pinf.min, pinf.min + name.length);
				default: haxe.macro.Context.error("Should be a markup node", expr.pos);
				}

				var inf = { fields : [], declaredIds : new Map(), inits : [], hasContent : false, useThis: false};
				var initExpr = @:privateAccess Macros.buildComponentsInit(root, inf, expr.pos, false);
				switch( initExpr.expr ) {
				case EBlock(el):
					var t = comp.baseType;
					el.unshift(macro var tmp = null);
					el.push(macro (cast tmp.obj : $t));
				default: throw "assert";
				}
				if( inf.inits.length > 0 ) {
					inf.inits.push({ expr : initExpr.expr, pos : initExpr.pos });
					initExpr.expr = EBlock(inf.inits);
				}
				return initExpr;

			} catch( e : Error ) {
				haxe.macro.Context.error(e.message, @:privateAccess Macros.makePos(expr.pos,e.pmin,e.pmax));
			}

		default:
			haxe.macro.Context.error("Should be a markup expression", expr.pos);
		}
		return null;
	}

	@:persistent static var COMPONENTS = new Map<String,Component<Dynamic,Dynamic>>();

}
