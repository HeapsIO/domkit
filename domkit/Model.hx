package domkit;

#if domkit_heaps
typedef Model<T> = h2d.Object;
#else
interface Model<T:Model<T>> {
	var dom : Properties<T>;
	var parent(default,never) : T;
	function getChildren() : Array<T>;
	function getChildRefPosition( first : Bool ) : Int;
}
#end
