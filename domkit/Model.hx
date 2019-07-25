package domkit;

interface Model<T:Model<T>> {
	var dom : Properties<T>;
	var parent(default,never) : T;
	function getChildren() : Array<T>;
}