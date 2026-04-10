component hint="Token-Oriented Object Notation (TOON) encode/decode — public API for JSON and CFML data" {

	variables.LIST_ITEM_MARKER  = "-";
	variables.LIST_ITEM_PREFIX = "- ";
	variables.COMMA            = ",";
	variables.COLON            = ":";
	variables.SPACE            = " ";
	variables.PIPE             = "|";
	variables.TAB              = chr( 9 );
	variables.NEWLINE          = chr( 10 );

	public string function encodeFromJson( required string json, struct options = {} ) {
		var data = DeserializeJSON( arguments.json );
		return encodeFromCfml( data, arguments.options );
	}

	public string function encodeFromCfml( required any data, struct options = {} ) {
		var opts = _resolveEncodeOptions( arguments.options );
		var normalized = _normalizeValue( arguments.data );
		var lines = _encodeJsonValueLines( normalized, 0, opts );
		return arrayToList( lines, variables.NEWLINE );
	}

	public any function decodeToCfml( required string toon, struct options = {} ) {
		var opts = _resolveDecodeOptions( arguments.options );
		var lines = _splitLines( arguments.toon );
		var events = [];
		_decodeStreamToEvents( lines, events, opts );
		var root = _buildValueFromEvents( events );
		if ( opts.expandPaths == "safe" ) {
			return _expandPathsSafe( root, opts.strict );
		}
		return root;
	}

	public string function decodeToJson( required string toon, struct options = {} ) {
		var value = decodeToCfml( arguments.toon, arguments.options );
		return SerializeJSON( value );
	}

	public struct function defaultEncodeOptions() {
		return { indent: 2, delimiter: "comma", keyFolding: "off" };
	}

	public struct function defaultDecodeOptions() {
		return { indent: 2, strict: true, expandPaths: "off" };
	}

	private struct function _resolveEncodeOptions( struct options ) {
		var o = arguments.options ?: {};
		return {
			  indent      : structKeyExists( o, "indent" ) ? val( o.indent ) : 2
			, delimiter   : structKeyExists( o, "delimiter" ) ? o.delimiter : "comma"
			, keyFolding  : structKeyExists( o, "keyFolding" ) ? o.keyFolding : "off"
			, delimChar   : _delimiterChar( structKeyExists( o, "delimiter" ) ? o.delimiter : "comma" )
		};
	}

	private struct function _resolveDecodeOptions( struct options ) {
		var o = arguments.options ?: {};
		return {
			  indent      : structKeyExists( o, "indent" ) ? val( o.indent ) : 2
			, strict      : structKeyExists( o, "strict" ) ? o.strict : true
			, expandPaths : structKeyExists( o, "expandPaths" ) ? o.expandPaths : "off"
		};
	}

	private string function _delimiterChar( required string name ) {
		switch ( lCase( arguments.name ) ) {
			case "tab": return variables.TAB;
			case "pipe": return variables.PIPE;
			default: return variables.COMMA;
		}
	}

	private array function _splitLines( required string s ) {
		var t = replace( arguments.s, chr( 13 ), "", "all" );
		return listToArray( t, variables.NEWLINE, true );
	}

	private boolean function _mapEntryNull( required any m, required string key ) {
		return isInstanceOf( arguments.m, "java.util.Map" )
			&& createObject( "java", "java.util.Objects" ).isNull( arguments.m.get( JavaCast( "string", arguments.key ) ) );
	}

	private any function _structEntryPresent( required struct s, required string key ) {
		return isInstanceOf( arguments.s, "java.util.Map" )
			? arguments.s.get( JavaCast( "string", arguments.key ) )
			: arguments.s[ arguments.key ];
	}

	private any function _normalizeValue( required any value ) {
		if ( IsNull( arguments.value ) ) {
			return JavaCast( "null", "" );
		}
		if ( IsArray( arguments.value ) ) {
			var outA = [];
			for ( var i = 1; i <= arrayLen( arguments.value ); i++ ) {
				arrayAppend( outA, _normalizeValue( arguments.value[ i ] ) );
			}
			return outA;
		}
		if ( IsStruct( arguments.value ) ) {
			var outS = {};
			var src = arguments.value;
			var keys = StructKeyArray( src );
			for ( var ki = 1; ki <= ArrayLen( keys ); ki++ ) {
				var kk = keys[ ki ];
				if ( _mapEntryNull( src, kk ) ) {
					outS[ kk ] = JavaCast( "null", "" );
					continue;
				}
				outS[ kk ] = _normalizeValue( _structEntryPresent( src, kk ) );
			}
			return outS;
		}
		if ( IsQuery( arguments.value ) ) {
			return arguments.value;
		}
		if ( IsDate( arguments.value ) ) {
			return DateTimeFormat( arguments.value, "yyyy-mm-dd'T'HH:nn:ssXXX" );
		}
		if ( IsBoolean( arguments.value ) ) {
			return arguments.value;
		}
		if ( IsNumeric( arguments.value ) ) {
			try {
				var jd = createObject( "java", "java.lang.Double" ).valueOf( JavaCast( "double", arguments.value ) );
				if ( !jd.isFinite() ) {
					return JavaCast( "null", "" );
				}
			} catch ( any e0 ) {}
			return arguments.value;
		}
		if ( IsSimpleValue( arguments.value ) ) {
			return toString( arguments.value );
		}
		return JavaCast( "null", "" );
	}

	private array function _queryColumnKeys( required query q ) {
		var raw = listToArray( arguments.q.columnList );
		for ( var ri = 1; ri <= arrayLen( raw ); ri++ ) {
			raw[ ri ] = trim( raw[ ri ] );
		}
		return raw;
	}

	private boolean function _valueIsTabularCell( required any v ) {
		if ( IsNull( arguments.v ) ) {
			return true;
		}
		if ( IsNumeric( arguments.v ) || IsBoolean( arguments.v ) ) {
			return true;
		}
		if ( IsDate( arguments.v ) ) {
			return true;
		}
		if ( IsSimpleValue( arguments.v ) ) {
			return true;
		}
		return false;
	}

	private boolean function _queryIsTabularEncodable( required query q, required array cols ) {
		if ( !arguments.q.recordCount ) {
			return true;
		}
		for ( var tr = 1; tr <= arguments.q.recordCount; tr++ ) {
			for ( var tc = 1; tc <= arrayLen( arguments.cols ); tc++ ) {
				if ( !_valueIsTabularCell( arguments.q[ arguments.cols[ tc ] ][ tr ] ) ) {
					return false;
				}
			}
		}
		return true;
	}

	private array function _queryToArrayOfStructs( required query q ) {
		var cols = _queryColumnKeys( arguments.q );
		var rows = [];
		var r = arguments.q.recordCount;
		for ( var i = 1; i <= r; i++ ) {
			var row = {};
			for ( var c = 1; c <= arrayLen( cols ); c++ ) {
				var col = cols[ c ];
				row[ col ] = arguments.q[ col ][ i ];
			}
			arrayAppend( rows, row );
		}
		return rows;
	}

	private array function _encodeQueryTabularLines( required query q, required numeric depth, required struct options, any encKey = javacast( "null", "" ) ) {
		var delim = arguments.options.delimChar;
		var cols = _queryColumnKeys( arguments.q );
		if ( !_queryIsTabularEncodable( arguments.q, cols ) ) {
			var asArr = _queryToArrayOfStructs( arguments.q );
			return _encodeArrayLinesList( asArr, arguments.depth, arguments.options, arguments.encKey );
		}
		var lines = [];
		var hdrT = { delimiterChar: delim, fields: cols };
		if ( !IsNull( arguments.encKey ) ) {
			hdrT.key = arguments.encKey;
		}
		arrayAppend( lines, _indentedLine( arguments.depth, _formatHeader( arguments.q.recordCount, hdrT ), arguments.options.indent ) );
		for ( var tr = 1; tr <= arguments.q.recordCount; tr++ ) {
			var cells = [];
			for ( var tf = 1; tf <= arrayLen( cols ); tf++ ) {
				arrayAppend( cells, arguments.q[ cols[ tf ] ][ tr ] );
			}
			arrayAppend( lines, _indentedLine( arguments.depth + 1, _encodeAndJoinPrimitives( cells, delim ), arguments.options.indent ) );
		}
		return lines;
	}

	private array function _encodeQueryAsListItemLines( required query q, required numeric depth, required struct options ) {
		var delim = arguments.options.delimChar;
		var cols = _queryColumnKeys( arguments.q );
		var lines = [];
		if ( !_queryIsTabularEncodable( arguments.q, cols ) ) {
			var asArrF = _queryToArrayOfStructs( arguments.q );
			arrayAppend( lines, _indentedListItem( arguments.depth, _formatHeader( arrayLen( asArrF ), { delimiterChar: delim } ), arguments.options.indent ) );
			for ( var li = 1; li <= arrayLen( asArrF ); li++ ) {
				arrayAppend( lines, _encodeListItemValueLines( asArrF[ li ], arguments.depth + 1, arguments.options ), true );
			}
			return lines;
		}
		var hdrT = { delimiterChar: delim, fields: cols };
		arrayAppend( lines, _indentedListItem( arguments.depth, _formatHeader( arguments.q.recordCount, hdrT ), arguments.options.indent ) );
		for ( var tr = 1; tr <= arguments.q.recordCount; tr++ ) {
			var cells = [];
			for ( var tf = 1; tf <= arrayLen( cols ); tf++ ) {
				arrayAppend( cells, arguments.q[ cols[ tf ] ][ tr ] );
			}
			arrayAppend( lines, _indentedLine( arguments.depth + 2, _encodeAndJoinPrimitives( cells, delim ), arguments.options.indent ) );
		}
		return lines;
	}

	private string function _canonicalNumber( required numeric n ) {
		try {
			return createObject( "java", "java.math.BigDecimal" ).valueOf( JavaCast( "double", arguments.n ) ).stripTrailingZeros().toPlainString();
		} catch ( any e ) {
			return toString( arguments.n );
		}
	}

	private string function _escapeString( required string value ) {
		var v = arguments.value;
		v = replace( v, "\", "\\", "all" );
		v = replace( v, """", "\""", "all" );
		v = replace( v, chr( 10 ), "\n", "all" );
		v = replace( v, chr( 13 ), "\r", "all" );
		v = replace( v, chr( 9 ), "\t", "all" );
		return v;
	}

	private boolean function _isBooleanOrNullLiteral( required string token ) {
		var t = arguments.token;
		return ( t == "true" || t == "false" || t == "null" );
	}

	private boolean function _isNumericLiteral( required string token ) {
		var t = arguments.token;
		if ( !len( t ) ) {
			return false;
		}
		if ( len( t ) > 1 && left( t, 1 ) == "0" && mid( t, 2, 1 ) != "." ) {
			return false;
		}
		if ( !IsNumeric( t ) ) {
			return false;
		}
		try {
			var d = val( t );
			var jd = createObject( "java", "java.lang.Double" ).valueOf( JavaCast( "double", d ) );
			return jd.isFinite();
		} catch ( any e ) {
			return false;
		}
	}

	private boolean function _isNumericLike( required string value ) {
		if ( reFind( "^-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?$", arguments.value ) ) {
			return true;
		}
		if ( reFind( "^0\d+$", arguments.value ) ) {
			return true;
		}
		return false;
	}

	private boolean function _isValidUnquotedKey( required string key ) {
		return reFind( "^[A-Za-z_][A-Za-z0-9_.]*$", arguments.key ) == 1;
	}

	private boolean function _isSafeUnquoted( required string value, required string delimiter ) {
		var v = arguments.value;
		if ( !len( v ) ) {
			return false;
		}
		if ( v != trim( v ) ) {
			return false;
		}
		if ( _isBooleanOrNullLiteral( v ) || _isNumericLike( v ) ) {
			return false;
		}
		if ( find( variables.COLON, v ) ) {
			return false;
		}
		if ( find( """", v ) || find( "\", v ) ) {
			return false;
		}
		if ( find( "[", v ) || find( "]", v ) || find( "{", v ) || find( "}", v ) ) {
			return false;
		}
		if ( reFind( "[\n\r\t]", v ) ) {
			return false;
		}
		if ( len( arguments.delimiter ) && find( arguments.delimiter, v ) ) {
			return false;
		}
		if ( left( v, 1 ) == variables.LIST_ITEM_MARKER ) {
			return false;
		}
		return true;
	}

	private string function _encodeStringLiteral( required string value, required string delimiter ) {
		if ( _isSafeUnquoted( arguments.value, arguments.delimiter ) ) {
			return arguments.value;
		}
		return """" & _escapeString( arguments.value ) & """";
	}

	private string function _encodeKey( required string key ) {
		if ( _isValidUnquotedKey( arguments.key ) ) {
			return arguments.key;
		}
		return """" & _escapeString( arguments.key ) & """";
	}

	private string function _encodePrimitive( required any value, required string delimiter ) {
		if ( IsNull( arguments.value ) ) {
			return "null";
		}
		if ( IsNumeric( arguments.value ) ) {
			return _canonicalNumber( arguments.value );
		}
		if ( IsBoolean( arguments.value ) ) {
			return arguments.value ? "true" : "false";
		}
		if ( IsDate( arguments.value ) ) {
			return _encodeStringLiteral( DateTimeFormat( arguments.value, "yyyy-mm-dd'T'HH:nn:ssXXX" ), arguments.delimiter );
		}
		return _encodeStringLiteral( toString( arguments.value ), arguments.delimiter );
	}

	private string function _formatHeader( required numeric length, struct opts ) {
		var o = arguments.opts;
		var delim = o.delimiterChar;
		var key = structKeyExists( o, "key" ) ? o.key : "";
		var fields = structKeyExists( o, "fields" ) ? o.fields : javacast( "null", "" );
		var header = "";
		if ( len( key ) ) {
			header &= _encodeKey( key );
		}
		header &= "[" & int( arguments.length );
		if ( delim != variables.COMMA ) {
			header &= delim;
		}
		header &= "]";
		if ( !IsNull( fields ) && IsArray( fields ) && arrayLen( fields ) ) {
			var parts = [];
			for ( var f = 1; f <= arrayLen( fields ); f++ ) {
				arrayAppend( parts, _encodeKey( fields[ f ] ) );
			}
			header &= "{" & arrayToList( parts, delim ) & "}";
		}
		header &= variables.COLON;
		return header;
	}

	private string function _encodeAndJoinPrimitives( required array values, required string delimiter ) {
		var parts = [];
		for ( var i = 1; i <= arrayLen( arguments.values ); i++ ) {
			arrayAppend( parts, _encodePrimitive( arguments.values[ i ], arguments.delimiter ) );
		}
		return arrayToList( parts, arguments.delimiter );
	}

	private string function _encodeInlineArrayLine( required array values, required string delimiter, string key = "" ) {
		var hdrOpts = { delimiterChar: arguments.delimiter };
		if ( len( arguments.key ) ) {
			hdrOpts.key = arguments.key;
		}
		var header = _formatHeader( arrayLen( arguments.values ), hdrOpts );
		if ( !arrayLen( arguments.values ) ) {
			return header;
		}
		return header & variables.SPACE & _encodeAndJoinPrimitives( arguments.values, arguments.delimiter );
	}

	private string function _indentedLine( required numeric depth, required string content, required numeric indentSize ) {
		return repeatString( variables.SPACE, arguments.indentSize * arguments.depth ) & arguments.content;
	}

	private string function _indentedListItem( required numeric depth, required string content, required numeric indentSize ) {
		return _indentedLine( arguments.depth, variables.LIST_ITEM_PREFIX & arguments.content, arguments.indentSize );
	}

	private boolean function _isJsonPrimitive( required any v ) {
		if ( IsNull( arguments.v ) ) {
			return true;
		}
		if ( IsNumeric( arguments.v ) ) {
			return true;
		}
		if ( IsBoolean( arguments.v ) ) {
			return true;
		}
		if ( IsSimpleValue( arguments.v ) && !IsDate( arguments.v ) ) {
			return true;
		}
		return false;
	}

	private boolean function _isJsonArray( required any v ) {
		return IsArray( arguments.v );
	}

	private boolean function _isJsonObject( required any v ) {
		return IsStruct( arguments.v );
	}

	private boolean function _isEmptyObject( required struct s ) {
		return structIsEmpty( arguments.s );
	}

	private boolean function _isArrayOfPrimitives( required array a ) {
		if ( !arrayLen( arguments.a ) ) {
			return true;
		}
		for ( var i = 1; i <= arrayLen( arguments.a ); i++ ) {
			if ( !_isJsonPrimitive( arguments.a[ i ] ) ) {
				return false;
			}
		}
		return true;
	}

	private boolean function _isArrayOfArrays( required array a ) {
		if ( !arrayLen( arguments.a ) ) {
			return true;
		}
		for ( var i = 1; i <= arrayLen( arguments.a ); i++ ) {
			if ( !_isJsonArray( arguments.a[ i ] ) ) {
				return false;
			}
		}
		return true;
	}

	private boolean function _isArrayOfObjects( required array a ) {
		if ( !arrayLen( arguments.a ) ) {
			return true;
		}
		for ( var i = 1; i <= arrayLen( arguments.a ); i++ ) {
			if ( !_isJsonObject( arguments.a[ i ] ) ) {
				return false;
			}
		}
		return true;
	}

	private boolean function _isTabularArray( required array rows, required array header ) {
		for ( var r = 1; r <= arrayLen( arguments.rows ); r++ ) {
			var row = arguments.rows[ r ];
			var keys = structKeyArray( row );
			if ( arrayLen( keys ) != arrayLen( arguments.header ) ) {
				return false;
			}
			for ( var h = 1; h <= arrayLen( arguments.header ); h++ ) {
				var hk = arguments.header[ h ];
				if ( !structKeyExists( row, hk ) ) {
					return false;
				}
				if ( !_valueIsTabularCell( row[ hk ] ) ) {
					return false;
				}
			}
		}
		return true;
	}

	private array function _extractTabularHeader( required array rows ) {
		if ( !arrayLen( arguments.rows ) ) {
			return [];
		}
		var firstRow = arguments.rows[ 1 ];
		var firstKeys = structKeyArray( firstRow );
		if ( !arrayLen( firstKeys ) ) {
			return [];
		}
		if ( !_isTabularArray( arguments.rows, firstKeys ) ) {
			return [];
		}
		return firstKeys;
	}

	private array function _encodeJsonValueLines( required any value, required numeric depth, required struct options ) {
		var lines = [];
		if ( _isJsonPrimitive( arguments.value ) ) {
			var ep = _encodePrimitive( arguments.value, arguments.options.delimChar );
			if ( len( ep ) || IsNull( arguments.value ) || IsBoolean( arguments.value ) || IsNumeric( arguments.value ) ) {
				arrayAppend( lines, ep );
			}
			return lines;
		}
		if ( IsQuery( arguments.value ) ) {
			arrayAppend( lines, _encodeQueryTabularLines( arguments.value, arguments.depth, arguments.options, javacast( "null", "" ) ), true );
			return lines;
		}
		if ( _isJsonArray( arguments.value ) ) {
			arrayAppend( lines, _encodeArrayLinesList( arguments.value, arguments.depth, arguments.options, javacast( "null", "" ) ), true );
			return lines;
		}
		if ( _isJsonObject( arguments.value ) ) {
			arrayAppend( lines, _encodeObjectLines( arguments.value, arguments.depth, arguments.options ), true );
			return lines;
		}
		return lines;
	}

	private array function _sortedStructKeys( required struct s ) {
		var keys = structKeyArray( arguments.s );
		arraySort( keys, "text", "asc" );
		return keys;
	}

	private array function _encodeObjectLines( required struct value, required numeric depth, required struct options ) {
		var lines = [];
		var keys = _sortedStructKeys( arguments.value );
		for ( var i = 1; i <= arrayLen( keys ); i++ ) {
			var k = keys[ i ];
			var ek = _encodeKey( k );
			if ( _mapEntryNull( arguments.value, k ) ) {
				arrayAppend( lines, _indentedLine( arguments.depth, ek & variables.COLON & variables.SPACE & "null", arguments.options.indent ) );
				continue;
			}
			var val = _structEntryPresent( arguments.value, k );
			if ( _isJsonPrimitive( val ) ) {
				arrayAppend( lines, _indentedLine( arguments.depth, ek & variables.COLON & variables.SPACE & _encodePrimitive( val, arguments.options.delimChar ), arguments.options.indent ) );
			} else if ( IsQuery( val ) ) {
				arrayAppend( lines, _encodeQueryTabularLines( val, arguments.depth, arguments.options, k ), true );
			} else if ( _isJsonArray( val ) ) {
				arrayAppend( lines, _encodeArrayLinesList( val, arguments.depth, arguments.options, k ), true );
			} else if ( _isJsonObject( val ) ) {
				arrayAppend( lines, _indentedLine( arguments.depth, ek & variables.COLON, arguments.options.indent ) );
				if ( !_isEmptyObject( val ) ) {
					arrayAppend( lines, _encodeObjectLines( val, arguments.depth + 1, arguments.options ), true );
				}
			}
		}
		return lines;
	}

	private array function _encodeArrayLinesList( required array value, required numeric depth, required struct options, any key = javacast( "null", "" ) ) {
		var lines = [];
		var delim = arguments.options.delimChar;
		if ( !arrayLen( arguments.value ) ) {
			var hdrEmpty = { delimiterChar: delim };
			if ( !IsNull( arguments.key ) ) {
				hdrEmpty.key = arguments.key;
			}
			arrayAppend( lines, _indentedLine( arguments.depth, _formatHeader( 0, hdrEmpty ), arguments.options.indent ) );
			return lines;
		}
		if ( _isArrayOfPrimitives( arguments.value ) ) {
			arrayAppend( lines, _indentedLine( arguments.depth, _encodeInlineArrayLine( arguments.value, delim, IsNull( arguments.key ) ? "" : arguments.key ), arguments.options.indent ) );
			return lines;
		}
		if ( _isArrayOfArrays( arguments.value ) ) {
			var allPrimInner = true;
			for ( var ii = 1; ii <= arrayLen( arguments.value ); ii++ ) {
				if ( !_isArrayOfPrimitives( arguments.value[ ii ] ) ) {
					allPrimInner = false;
					break;
				}
			}
			if ( allPrimInner ) {
				var hdrA = { delimiterChar: delim };
				if ( !IsNull( arguments.key ) ) {
					hdrA.key = arguments.key;
				}
				arrayAppend( lines, _indentedLine( arguments.depth, _formatHeader( arrayLen( arguments.value ), hdrA ), arguments.options.indent ) );
				for ( var ai = 1; ai <= arrayLen( arguments.value ); ai++ ) {
					var arr = arguments.value[ ai ];
					arrayAppend( lines, _indentedListItem( arguments.depth + 1, _encodeInlineArrayLine( arr, delim, "" ), arguments.options.indent ) );
				}
				return lines;
			}
		}
		if ( _isArrayOfObjects( arguments.value ) ) {
			var tabHeader = _extractTabularHeader( arguments.value );
			if ( arrayLen( tabHeader ) ) {
				var hdrT = { delimiterChar: delim, fields: tabHeader };
				if ( !IsNull( arguments.key ) ) {
					hdrT.key = arguments.key;
				}
				arrayAppend( lines, _indentedLine( arguments.depth, _formatHeader( arrayLen( arguments.value ), hdrT ), arguments.options.indent ) );
				for ( var tr = 1; tr <= arrayLen( arguments.value ); tr++ ) {
					var row = arguments.value[ tr ];
					var cells = [];
					for ( var tf = 1; tf <= arrayLen( tabHeader ); tf++ ) {
						arrayAppend( cells, row[ tabHeader[ tf ] ] );
					}
					arrayAppend( lines, _indentedLine( arguments.depth + 1, _encodeAndJoinPrimitives( cells, delim ), arguments.options.indent ) );
				}
				return lines;
			}
		}
		var hdrM = { delimiterChar: delim };
		if ( !IsNull( arguments.key ) ) {
			hdrM.key = arguments.key;
		}
		arrayAppend( lines, _indentedLine( arguments.depth, _formatHeader( arrayLen( arguments.value ), hdrM ), arguments.options.indent ) );
		for ( var mi = 1; mi <= arrayLen( arguments.value ); mi++ ) {
			arrayAppend( lines, _encodeListItemValueLines( arguments.value[ mi ], arguments.depth + 1, arguments.options ), true );
		}
		return lines;
	}

	private array function _encodeListItemValueLines( required any value, required numeric depth, required struct options ) {
		var lines = [];
		var delim = arguments.options.delimChar;
		if ( _isJsonPrimitive( arguments.value ) ) {
			arrayAppend( lines, _indentedListItem( arguments.depth, _encodePrimitive( arguments.value, delim ), arguments.options.indent ) );
			return lines;
		}
		if ( IsQuery( arguments.value ) ) {
			arrayAppend( lines, _encodeQueryAsListItemLines( arguments.value, arguments.depth, arguments.options ), true );
			return lines;
		}
		if ( _isJsonArray( arguments.value ) ) {
			if ( _isArrayOfPrimitives( arguments.value ) ) {
				arrayAppend( lines, _indentedListItem( arguments.depth, _encodeInlineArrayLine( arguments.value, delim, "" ), arguments.options.indent ) );
				return lines;
			}
			arrayAppend( lines, _indentedListItem( arguments.depth, _formatHeader( arrayLen( arguments.value ), { delimiterChar: delim } ), arguments.options.indent ) );
			for ( var li = 1; li <= arrayLen( arguments.value ); li++ ) {
				arrayAppend( lines, _encodeListItemValueLines( arguments.value[ li ], arguments.depth + 1, arguments.options ), true );
			}
			return lines;
		}
		if ( _isJsonObject( arguments.value ) ) {
			arrayAppend( lines, _encodeObjectAsListItemLines( arguments.value, arguments.depth, arguments.options ), true );
			return lines;
		}
		return lines;
	}

	private array function _encodeObjectAsListItemLines( required struct obj, required numeric depth, required struct options ) {
		var lines = [];
		var delim = arguments.options.delimChar;
		if ( _isEmptyObject( arguments.obj ) ) {
			arrayAppend( lines, _indentedLine( arguments.depth, variables.LIST_ITEM_MARKER, arguments.options.indent ) );
			return lines;
		}
		var keys = structKeyArray( arguments.obj );
		var firstKey = keys[ 1 ];
		var firstVal = arguments.obj[ firstKey ];
		var restKeys = [];
		for ( var rk = 2; rk <= arrayLen( keys ); rk++ ) {
			arrayAppend( restKeys, keys[ rk ] );
		}
		var ek = _encodeKey( firstKey );
		if ( IsQuery( firstVal ) ) {
			var colsQ = _queryColumnKeys( firstVal );
			if ( _queryIsTabularEncodable( firstVal, colsQ ) ) {
				var hdrLineQ = { delimiterChar: delim, key: firstKey, fields: colsQ };
				arrayAppend( lines, _indentedListItem( arguments.depth, _formatHeader( firstVal.recordCount, hdrLineQ ), arguments.options.indent ) );
				for ( var wrq = 1; wrq <= firstVal.recordCount; wrq++ ) {
					var wcellsQ = [];
					for ( var wfq = 1; wfq <= arrayLen( colsQ ); wfq++ ) {
						arrayAppend( wcellsQ, firstVal[ colsQ[ wfq ] ][ wrq ] );
					}
					arrayAppend( lines, _indentedLine( arguments.depth + 2, _encodeAndJoinPrimitives( wcellsQ, delim ), arguments.options.indent ) );
				}
			} else {
				var asArrQ = _queryToArrayOfStructs( firstVal );
				arrayAppend( lines, _indentedListItem( arguments.depth, ek & _formatHeader( arrayLen( asArrQ ), { delimiterChar: delim } ), arguments.options.indent ) );
				for ( var xiq = 1; xiq <= arrayLen( asArrQ ); xiq++ ) {
					arrayAppend( lines, _encodeListItemValueLines( asArrQ[ xiq ], arguments.depth + 2, arguments.options ), true );
				}
			}
			if ( arrayLen( restKeys ) ) {
				var restObjQ = {};
				for ( var riq = 1; riq <= arrayLen( restKeys ); riq++ ) {
					var rk0q = restKeys[ riq ];
					restObjQ[ rk0q ] = arguments.obj[ rk0q ];
				}
				arrayAppend( lines, _encodeObjectLines( restObjQ, arguments.depth + 1, arguments.options ), true );
			}
			return lines;
		}
		if ( _isJsonArray( firstVal ) && _isArrayOfObjects( firstVal ) ) {
			var th = _extractTabularHeader( firstVal );
			if ( arrayLen( th ) ) {
				var hdrLine = { delimiterChar: delim, key: firstKey, fields: th };
				arrayAppend( lines, _indentedListItem( arguments.depth, _formatHeader( arrayLen( firstVal ), hdrLine ), arguments.options.indent ) );
				for ( var wr = 1; wr <= arrayLen( firstVal ); wr++ ) {
					var wrow = firstVal[ wr ];
					var wcells = [];
					for ( var wf = 1; wf <= arrayLen( th ); wf++ ) {
						arrayAppend( wcells, wrow[ th[ wf ] ] );
					}
					arrayAppend( lines, _indentedLine( arguments.depth + 2, _encodeAndJoinPrimitives( wcells, delim ), arguments.options.indent ) );
				}
				if ( arrayLen( restKeys ) ) {
					var restObj = {};
					for ( var ri = 1; ri <= arrayLen( restKeys ); ri++ ) {
						var rk0 = restKeys[ ri ];
						restObj[ rk0 ] = arguments.obj[ rk0 ];
					}
					arrayAppend( lines, _encodeObjectLines( restObj, arguments.depth + 1, arguments.options ), true );
				}
				return lines;
			}
		}
		if ( _isJsonPrimitive( firstVal ) ) {
			arrayAppend( lines, _indentedListItem( arguments.depth, ek & variables.COLON & variables.SPACE & _encodePrimitive( firstVal, delim ), arguments.options.indent ) );
		} else if ( _isJsonArray( firstVal ) ) {
			if ( !arrayLen( firstVal ) ) {
				arrayAppend( lines, _indentedListItem( arguments.depth, ek & _formatHeader( 0, { delimiterChar: delim } ), arguments.options.indent ) );
			} else if ( _isArrayOfPrimitives( firstVal ) ) {
				arrayAppend( lines, _indentedListItem( arguments.depth, ek & _encodeInlineArrayLine( firstVal, delim, "" ), arguments.options.indent ) );
			} else {
				arrayAppend( lines, _indentedListItem( arguments.depth, ek & _formatHeader( arrayLen( firstVal ), { delimiterChar: delim } ), arguments.options.indent ) );
				for ( var xi = 1; xi <= arrayLen( firstVal ); xi++ ) {
					arrayAppend( lines, _encodeListItemValueLines( firstVal[ xi ], arguments.depth + 2, arguments.options ), true );
				}
			}
		} else if ( _isJsonObject( firstVal ) ) {
			arrayAppend( lines, _indentedListItem( arguments.depth, ek & variables.COLON, arguments.options.indent ) );
			if ( !_isEmptyObject( firstVal ) ) {
				arrayAppend( lines, _encodeObjectLines( firstVal, arguments.depth + 2, arguments.options ), true );
			}
		}
		if ( arrayLen( restKeys ) ) {
			var restObj2 = {};
			for ( var rj = 1; rj <= arrayLen( restKeys ); rj++ ) {
				var rk1 = restKeys[ rj ];
				restObj2[ rk1 ] = arguments.obj[ rk1 ];
			}
			arrayAppend( lines, _encodeObjectLines( restObj2, arguments.depth + 1, arguments.options ), true );
		}
		return lines;
	}

	private string function _unescapeString( required string value ) {
		var out = "";
		var i = 1;
		while ( i <= len( arguments.value ) ) {
			var ch = mid( arguments.value, i, 1 );
			if ( ch == "\" && i < len( arguments.value ) ) {
				var nx = mid( arguments.value, i + 1, 1 );
				if ( nx == "n" ) {
					out &= chr( 10 );
				} else if ( nx == "t" ) {
					out &= chr( 9 );
				} else if ( nx == "r" ) {
					out &= chr( 13 );
				} else if ( nx == "\" || nx == """" ) {
					out &= nx;
				} else {
					throw( type="cbtoon.SyntaxError", message="Invalid escape sequence: \#nx#" );
				}
				i += 2;
				continue;
			}
			out &= ch;
			i++;
		}
		return out;
	}

	private string function _parseStringLiteral( required string token ) {
		var t = trim( arguments.token );
		if ( left( t, 1 ) == """" ) {
			var cq = _findClosingQuote( t, 1 );
			if ( cq < 2 ) {
				throw( type="cbtoon.SyntaxError", message="Unterminated string: missing closing quote" );
			}
			if ( cq != len( t ) ) {
				throw( type="cbtoon.SyntaxError", message="Unexpected characters after closing quote" );
			}
			return _unescapeString( mid( t, 2, cq - 2 ) );
		}
		return t;
	}

	private boolean function _isNumericLiteralDecode( required string token ) {
		var t = arguments.token;
		if ( !len( t ) ) {
			return false;
		}
		if ( len( t ) > 1 && left( t, 1 ) == "0" && mid( t, 2, 1 ) != "." ) {
			return false;
		}
		if ( !IsNumeric( t ) ) {
			return false;
		}
		try {
			var jd = createObject( "java", "java.lang.Double" ).parseDouble( JavaCast( "string", t ) );
			return jd.isFinite();
		} catch ( any e ) {
			return false;
		}
	}

	private any function _parsePrimitiveToken( required string token ) {
		var t = trim( arguments.token );
		if ( !len( t ) ) {
			return "";
		}
		if ( left( t, 1 ) == """" ) {
			return _parseStringLiteral( t );
		}
		if ( _isNumericLiteralDecode( t ) ) {
			return val( t );
		}
		if ( _isBooleanOrNullLiteral( t ) ) {
			if ( t == "true" ) {
				return true;
			}
			if ( t == "false" ) {
				return false;
			}
			return JavaCast( "null", "" );
		}
		return t;
	}

	private struct function _parseKeyToken( required string content ) {
		var isQuoted = left( arguments.content, 1 ) == """";
		if ( isQuoted ) {
			var cq = _findClosingQuote( arguments.content, 1 );
			if ( cq < 2 ) {
				throw( type="cbtoon.SyntaxError", message="Unterminated quoted key" );
			}
			var key = _unescapeString( mid( arguments.content, 2, cq - 2 ) );
			if ( cq >= len( arguments.content ) || mid( arguments.content, cq + 1, 1 ) != variables.COLON ) {
				throw( type="cbtoon.SyntaxError", message="Missing colon after key" );
			}
			return { key: key, valueStart: cq + 2, wasQuoted: true };
		}
		var colonPos = _findUnquotedChar( arguments.content, variables.COLON );
		if ( colonPos < 1 ) {
			throw( type="cbtoon.SyntaxError", message="Missing colon after key" );
		}
		var keyU = trim( mid( arguments.content, 1, colonPos - 1 ) );
		return { key: keyU, valueStart: colonPos + 1, wasQuoted: false };
	}

	private numeric function _findClosingQuote( required string content, required numeric openPos ) {
		var i = openPos + 1;
		while ( i <= len( arguments.content ) ) {
			var ch = mid( arguments.content, i, 1 );
			if ( ch == "\" && i < len( arguments.content ) ) {
				i += 2;
				continue;
			}
			if ( ch == """" ) {
				return i;
			}
			i++;
		}
		return 0;
	}

	private numeric function _findUnquotedChar( required string content, required string char, numeric start = 1 ) {
		var inQ = false;
		var i = arguments.start;
		while ( i <= len( arguments.content ) ) {
			var ch = mid( arguments.content, i, 1 );
			if ( ch == "\" && inQ && i < len( arguments.content ) ) {
				i += 2;
				continue;
			}
			if ( ch == """" ) {
				inQ = !inQ;
				i++;
				continue;
			}
			if ( ch == arguments.char && !inQ ) {
				return i;
			}
			i++;
		}
		return 0;
	}

	private array function _parseDelimitedValues( required string input, required string delimiter ) {
		var values = [];
		var buf = "";
		var inQ = false;
		var i = 1;
		var dlen = len( arguments.delimiter );
		while ( i <= len( arguments.input ) ) {
			var ch = mid( arguments.input, i, 1 );
			if ( ch == "\" && inQ && i < len( arguments.input ) ) {
				buf &= ch & mid( arguments.input, i + 1, 1 );
				i += 2;
				continue;
			}
			if ( ch == """" ) {
				inQ = !inQ;
				buf &= ch;
				i++;
				continue;
			}
			if ( dlen == 1 && ch == arguments.delimiter && !inQ ) {
				arrayAppend( values, trim( buf ) );
				buf = "";
				i++;
				continue;
			}
			if ( dlen > 1 && i + dlen - 1 <= len( arguments.input ) && mid( arguments.input, i, dlen ) == arguments.delimiter && !inQ ) {
				arrayAppend( values, trim( buf ) );
				buf = "";
				i += dlen;
				continue;
			}
			buf &= ch;
			i++;
		}
		if ( len( buf ) || arrayLen( values ) ) {
			arrayAppend( values, trim( buf ) );
		}
		return values;
	}

	private struct function _parseBracketSegment( required string seg, required string defaultDelimiter ) {
		var c = arguments.seg;
		var delim = arguments.defaultDelimiter;
		if ( len( c ) && right( c, 1 ) == variables.TAB ) {
			delim = variables.TAB;
			c = left( c, len( c ) - 1 );
		} else if ( len( c ) && right( c, 1 ) == variables.PIPE ) {
			delim = variables.PIPE;
			c = left( c, len( c ) - 1 );
		}
		c = trim( c );
		if ( !reFind( "^\d+$", c ) ) {
			throw( type="cbtoon.SyntaxError", message="Invalid array length: #arguments.seg#" );
		}
		return { length: int( val( c ) ), delimiter: delim };
	}

	private struct function _parseArrayHeaderLine( required string content, required string defaultDelimiter ) {
		var trimmed = trim( arguments.content );
		var bracketStart = 0;
		if ( left( trimmed, 1 ) == """" ) {
			var cq0 = _findClosingQuote( trimmed, 1 );
			if ( cq0 < 2 || mid( trimmed, cq0 + 1, 1 ) != "[" ) {
				return {};
			}
			bracketStart = find( "[", trimmed, cq0 + 1 );
		} else {
			bracketStart = find( "[", trimmed );
		}
		if ( bracketStart < 1 ) {
			return {};
		}
		var bracketEnd = find( "]", trimmed, bracketStart );
		if ( bracketEnd < 1 ) {
			return {};
		}
		var braceStart = find( "{", trimmed, bracketEnd );
		var colonAfterBracket = find( ":", trimmed, bracketEnd );
		if ( colonAfterBracket < 1 ) {
			return {};
		}
		var braceEnd = bracketEnd;
		if ( braceStart > 0 && braceStart < colonAfterBracket ) {
			var fbe = find( "}", trimmed, braceStart );
			if ( fbe > 0 && fbe < colonAfterBracket ) {
				braceEnd = fbe;
			}
		}
		var colonIndex = find( ":", trimmed, max( bracketEnd, braceEnd ) );
		if ( colonIndex < 1 ) {
			return {};
		}
		var key = JavaCast( "null", "" );
		if ( bracketStart > 1 ) {
			var rawKey = trim( mid( trimmed, 1, bracketStart - 1 ) );
			if ( left( rawKey, 1 ) == """" ) {
				key = _parseStringLiteral( rawKey );
			} else {
				key = rawKey;
			}
		}
		var afterColon = trim( mid( trimmed, colonIndex + 1, len( trimmed ) - colonIndex ) );
		var bracketContent = mid( trimmed, bracketStart + 1, bracketEnd - bracketStart - 1 );
		var pb = {};
		try {
			pb = _parseBracketSegment( bracketContent, arguments.defaultDelimiter );
		} catch ( any e ) {
			return {};
		}
		var fields = [];
		if ( braceStart > 0 && braceStart < colonIndex ) {
			var fbe2 = find( "}", trimmed, braceStart );
			if ( fbe2 > 0 && fbe2 < colonIndex ) {
				var inner = mid( trimmed, braceStart + 1, fbe2 - braceStart - 1 );
				var rawFields = _parseDelimitedValues( inner, pb.delimiter );
				for ( var fi = 1; fi <= arrayLen( rawFields ); fi++ ) {
					arrayAppend( fields, _parseStringLiteral( trim( rawFields[ fi ] ) ) );
				}
			}
		}
		return {
			  header: { key: key, length: pb.length, delimiter: pb.delimiter, fields: fields }
			, inlineValues: len( afterColon ) ? afterColon : ""
		};
	}

	private boolean function _isArrayHeaderContent( required string content ) {
		var t = trim( arguments.content );
		if ( left( t, 1 ) != "[" ) {
			return false;
		}
		return _findUnquotedChar( arguments.content, variables.COLON ) > 0;
	}

	private boolean function _isKeyValueLine( required struct line ) {
		var content = arguments.line.content;
		if ( left( content, 1 ) == """" ) {
			var cqi = _findClosingQuote( content, 1 );
			if ( cqi < 2 ) {
				return false;
			}
			return find( variables.COLON, content, cqi ) > 0;
		}
		return find( variables.COLON, content ) > 0;
	}

	private boolean function _isKeyValueContent( required string content ) {
		return _findUnquotedChar( arguments.content, variables.COLON ) > 0;
	}

	private boolean function _isDataRow( required string content, required string delimiter ) {
		var colonPos = find( variables.COLON, arguments.content );
		var delimPos = arguments.delimiter == variables.TAB ? find( variables.TAB, arguments.content ) : find( arguments.delimiter, arguments.content );
		if ( colonPos < 1 ) {
			return true;
		}
		if ( delimPos > 0 && delimPos < colonPos ) {
			return true;
		}
		return false;
	}

	private void function _assertExpectedCount( required numeric actual, required numeric expected, required string itemType, required struct options ) {
		if ( arguments.options.strict && arguments.actual != arguments.expected ) {
			throw( type="cbtoon.RangeError", message="Expected #arguments.expected# #arguments.itemType#, but got #arguments.actual#" );
		}
	}

	private void function _validateNoBlankLinesInRange( required numeric startLine, required numeric endLine, required array blankLines, required boolean strict, required string context ) {
		if ( !arguments.strict ) {
			return;
		}
		for ( var b = 1; b <= arrayLen( arguments.blankLines ); b++ ) {
			var bl = arguments.blankLines[ b ];
			if ( bl.lineNumber > arguments.startLine && bl.lineNumber < arguments.endLine ) {
				throw( type="cbtoon.SyntaxError", message="Line #bl.lineNumber#: Blank lines inside #arguments.context# are not allowed in strict mode" );
			}
		}
	}

	private void function _validateNoExtraTabularRows( any nextLine, required numeric rowDepth, required struct header ) {
		if ( isNull( arguments.nextLine ) ) {
			return;
		}
		if ( arguments.nextLine.depth == arguments.rowDepth && left( arguments.nextLine.content, 2 ) != variables.LIST_ITEM_PREFIX && _isDataRow( arguments.nextLine.content, arguments.header.delimiter ) ) {
			throw( type="cbtoon.RangeError", message="Expected #arguments.header.length# tabular rows, but found more" );
		}
	}

	private void function _validateNoExtraListItems( any nextLine, required numeric itemDepth, required numeric expectedCount ) {
		if ( isNull( arguments.nextLine ) ) {
			return;
		}
		if ( arguments.nextLine.depth == arguments.itemDepth && ( left( arguments.nextLine.content, 2 ) == variables.LIST_ITEM_PREFIX || arguments.nextLine.content == variables.LIST_ITEM_MARKER ) ) {
			throw( type="cbtoon.RangeError", message="Expected #arguments.expectedCount# list array items, but found more" );
		}
	}

	private void function _yieldObjectFromFields( required array fields, required array primitives, required array events ) {
		arrayAppend( arguments.events, { type: "startObject" } );
		for ( var i = 1; i <= arrayLen( arguments.fields ); i++ ) {
			arrayAppend( arguments.events, { type: "key", key: arguments.fields[ i ] } );
			arrayAppend( arguments.events, { type: "primitive", value: arguments.primitives[ i ] } );
		}
		arrayAppend( arguments.events, { type: "endObject" } );
	}

	private array function _parseLinesToStructs( required array rawLines, required numeric indentSize, required boolean strict, required struct scan ) {
		var out = [];
		for ( var i = 1; i <= arrayLen( arguments.rawLines ); i++ ) {
			var raw = arguments.rawLines[ i ];
			arguments.scan.lineNumber++;
			var lineNum = arguments.scan.lineNumber;
			var indent = 0;
			while ( indent < len( raw ) && mid( raw, indent + 1, 1 ) == variables.SPACE ) {
				indent++;
			}
			var content = mid( raw, indent + 1, len( raw ) - indent );
			if ( !len( trim( content ) ) ) {
				arrayAppend( arguments.scan.blankLines, { lineNumber: lineNum, indent: indent, depth: int( indent / arguments.indentSize ) } );
				continue;
			}
			var depth = int( indent / arguments.indentSize );
			if ( arguments.strict ) {
				var wsEnd = 0;
				while ( wsEnd < len( raw ) && ( mid( raw, wsEnd + 1, 1 ) == variables.SPACE || mid( raw, wsEnd + 1, 1 ) == variables.TAB ) ) {
					wsEnd++;
				}
				if ( wsEnd > 0 && find( variables.TAB, left( raw, wsEnd ) ) ) {
					throw( type="cbtoon.SyntaxError", message="Line #lineNum#: Tabs are not allowed in indentation in strict mode" );
				}
				if ( indent > 0 && indent mod arguments.indentSize != 0 ) {
					throw( type="cbtoon.SyntaxError", message="Line #lineNum#: Indentation must be exact multiple of #arguments.indentSize#, but found #indent# spaces" );
				}
			}
			arrayAppend( out, { raw: raw, indent: indent, content: content, depth: depth, lineNumber: lineNum } );
		}
		return out;
	}

	private any function _cursorPeek( required struct cursor ) {
		if ( arguments.cursor.index < arrayLen( arguments.cursor.lines ) ) {
			return arguments.cursor.lines[ arguments.cursor.index + 1 ];
		}
		return JavaCast( "null", "" );
	}

	private void function _cursorAdvance( required struct cursor ) {
		var ln = _cursorPeek( cursor );
		if ( !isNull( ln ) ) {
			arguments.cursor.index++;
			arguments.cursor.lastLine = ln;
		}
	}

	private boolean function _cursorAtEnd( required struct cursor ) {
		return isNull( _cursorPeek( cursor ) );
	}

	private void function _decodeStreamToEvents( required array rawLines, required array events, required struct options ) {
		var scan = { lineNumber: 0, blankLines: [] };
		var parsed = _parseLinesToStructs( rawLines, arguments.options.indent, arguments.options.strict, scan );
		var cursor = { lines: parsed, index: 0, lastLine: JavaCast( "null", "" ), blankLines: scan.blankLines };
		var first = _cursorPeek( cursor );
		if ( isNull( first ) ) {
			arrayAppend( arguments.events, { type: "startObject" } );
			arrayAppend( arguments.events, { type: "endObject" } );
			return;
		}
		if ( _isArrayHeaderContent( first.content ) ) {
			var ah0 = _parseArrayHeaderLine( first.content, variables.COMMA );
			if ( !structIsEmpty( ah0 ) ) {
				_cursorAdvance( cursor );
				_decodeArrayFromHeader( ah0.header, ah0.inlineValues, cursor, 0, arguments.options, arguments.events );
				return;
			}
		}
		_cursorAdvance( cursor );
		if ( _cursorAtEnd( cursor ) && !_isKeyValueLine( first ) ) {
			arrayAppend( arguments.events, { type: "primitive", value: _parsePrimitiveToken( trim( first.content ) ) } );
			return;
		}
		arrayAppend( arguments.events, { type: "startObject" } );
		_decodeKeyValue( first.content, cursor, 0, arguments.options, arguments.events );
		while ( !_cursorAtEnd( cursor ) ) {
			var ln = _cursorPeek( cursor );
			if ( isNull( ln ) || ln.depth != 0 ) {
				break;
			}
			_cursorAdvance( cursor );
			_decodeKeyValue( ln.content, cursor, 0, arguments.options, arguments.events );
		}
		arrayAppend( arguments.events, { type: "endObject" } );
	}

	private void function _decodeKeyValue( required string content, required struct cursor, required numeric baseDepth, required struct options, required array events ) {
		var arrayHeader = _parseArrayHeaderLine( arguments.content, variables.COMMA );
		if ( !structIsEmpty( arrayHeader ) && !isNull( arrayHeader.header.key ) && len( toString( arrayHeader.header.key ) ) ) {
			arrayAppend( arguments.events, { type: "key", key: arrayHeader.header.key } );
			_decodeArrayFromHeader( arrayHeader.header, arrayHeader.inlineValues, cursor, arguments.baseDepth, arguments.options, arguments.events );
			return;
		}
		var pk = _parseKeyToken( arguments.content );
		var rest = trim( mid( arguments.content, pk.valueStart, len( arguments.content ) - pk.valueStart + 1 ) );
		var keyEvt = { type: "key", key: pk.key };
		if ( pk.wasQuoted ) {
			keyEvt.wasQuoted = true;
		}
		arrayAppend( arguments.events, keyEvt );
		if ( !len( rest ) ) {
			var nextLine = _cursorPeek( cursor );
			if ( !isNull( nextLine ) && nextLine.depth > arguments.baseDepth ) {
				arrayAppend( arguments.events, { type: "startObject" } );
				_decodeObjectFields( cursor, arguments.baseDepth + 1, arguments.options, arguments.events );
				arrayAppend( arguments.events, { type: "endObject" } );
				return;
			}
			arrayAppend( arguments.events, { type: "startObject" } );
			arrayAppend( arguments.events, { type: "endObject" } );
			return;
		}
		arrayAppend( arguments.events, { type: "primitive", value: _parsePrimitiveToken( rest ) } );
	}

	private void function _decodeObjectFields( required struct cursor, required numeric baseDepth, required struct options, required array events ) {
		var computedDepth = JavaCast( "null", "" );
		while ( !_cursorAtEnd( cursor ) ) {
			var line = _cursorPeek( cursor );
			if ( isNull( line ) || line.depth < arguments.baseDepth ) {
				break;
			}
			if ( isNull( computedDepth ) && line.depth >= arguments.baseDepth ) {
				computedDepth = line.depth;
			}
			if ( !isNull( computedDepth ) && line.depth == computedDepth ) {
				_cursorAdvance( cursor );
				_decodeKeyValue( line.content, cursor, computedDepth, arguments.options, arguments.events );
			} else {
				break;
			}
		}
	}

	private void function _decodeArrayFromHeader( required struct header, required string inlineValues, required struct cursor, required numeric baseDepth, required struct options, required array events ) {
		arrayAppend( arguments.events, { type: "startArray", length: arguments.header.length } );
		if ( len( arguments.inlineValues ) ) {
			_decodeInlinePrimitiveArray( arguments.header, arguments.inlineValues, arguments.options, arguments.events );
			arrayAppend( arguments.events, { type: "endArray" } );
			return;
		}
		if ( IsArray( arguments.header.fields ) && arrayLen( arguments.header.fields ) ) {
			_decodeTabularArray( arguments.header, cursor, arguments.baseDepth, arguments.options, arguments.events );
			arrayAppend( arguments.events, { type: "endArray" } );
			return;
		}
		_decodeListArray( arguments.header, cursor, arguments.baseDepth, arguments.options, arguments.events );
		arrayAppend( arguments.events, { type: "endArray" } );
	}

	private void function _decodeInlinePrimitiveArray( required struct header, required string inlineValues, required struct options, required array events ) {
		if ( !len( trim( arguments.inlineValues ) ) ) {
			_assertExpectedCount( 0, arguments.header.length, "inline array items", arguments.options );
			return;
		}
		var primitives = [];
		var rawVals = _parseDelimitedValues( arguments.inlineValues, arguments.header.delimiter );
		for ( var ri = 1; ri <= arrayLen( rawVals ); ri++ ) {
			arrayAppend( primitives, _parsePrimitiveToken( rawVals[ ri ] ) );
		}
		_assertExpectedCount( arrayLen( primitives ), arguments.header.length, "inline array items", arguments.options );
		for ( var pi = 1; pi <= arrayLen( primitives ); pi++ ) {
			arrayAppend( arguments.events, { type: "primitive", value: primitives[ pi ] } );
		}
	}

	private void function _decodeTabularArray( required struct header, required struct cursor, required numeric baseDepth, required struct options, required array events ) {
		var rowDepth = arguments.baseDepth + 1;
		var rowCount = 0;
		var startLine = JavaCast( "null", "" );
		var endLine = JavaCast( "null", "" );
		while ( !_cursorAtEnd( cursor ) && rowCount < arguments.header.length ) {
			var line = _cursorPeek( cursor );
			if ( isNull( line ) || line.depth < rowDepth ) {
				break;
			}
			if ( line.depth == rowDepth ) {
				if ( isNull( startLine ) ) {
					startLine = line.lineNumber;
				}
				endLine = line.lineNumber;
				_cursorAdvance( cursor );
				var values = _parseDelimitedValues( line.content, arguments.header.delimiter );
				_assertExpectedCount( arrayLen( values ), arrayLen( arguments.header.fields ), "tabular row values", arguments.options );
				var primRow = [];
				for ( var vi = 1; vi <= arrayLen( values ); vi++ ) {
					arrayAppend( primRow, _parsePrimitiveToken( values[ vi ] ) );
				}
				_yieldObjectFromFields( arguments.header.fields, primRow, arguments.events );
				rowCount++;
			} else {
				break;
			}
		}
		_assertExpectedCount( rowCount, arguments.header.length, "tabular rows", arguments.options );
		if ( arguments.options.strict && !isNull( startLine ) && !isNull( endLine ) ) {
			_validateNoBlankLinesInRange( startLine, endLine, cursor.blankLines, arguments.options.strict, "tabular array" );
		}
		if ( arguments.options.strict ) {
			_validateNoExtraTabularRows( _cursorPeek( cursor ), rowDepth, arguments.header );
		}
	}

	private void function _decodeListArray( required struct header, required struct cursor, required numeric baseDepth, required struct options, required array events ) {
		var itemDepth = arguments.baseDepth + 1;
		var itemCount = 0;
		var startLine = JavaCast( "null", "" );
		var endLine = JavaCast( "null", "" );
		while ( !_cursorAtEnd( cursor ) && itemCount < arguments.header.length ) {
			var line = _cursorPeek( cursor );
			if ( isNull( line ) || line.depth < itemDepth ) {
				break;
			}
			var isListItem = ( left( line.content, 2 ) == variables.LIST_ITEM_PREFIX ) || ( line.content == variables.LIST_ITEM_MARKER );
			if ( line.depth == itemDepth && isListItem ) {
				if ( isNull( startLine ) ) {
					startLine = line.lineNumber;
				}
				endLine = line.lineNumber;
				_decodeListItem( cursor, itemDepth, arguments.options, arguments.events );
				var cur = cursor.lastLine;
				if ( !isNull( cur ) ) {
					endLine = cur.lineNumber;
				}
				itemCount++;
			} else {
				break;
			}
		}
		_assertExpectedCount( itemCount, arguments.header.length, "list array items", arguments.options );
		if ( arguments.options.strict && !isNull( startLine ) && !isNull( endLine ) ) {
			_validateNoBlankLinesInRange( startLine, endLine, cursor.blankLines, arguments.options.strict, "list array" );
		}
		if ( arguments.options.strict ) {
			_validateNoExtraListItems( _cursorPeek( cursor ), itemDepth, arguments.header.length );
		}
	}

	private void function _decodeListItem( required struct cursor, required numeric baseDepth, required struct options, required array events ) {
		var line = _cursorPeek( cursor );
		if ( isNull( line ) ) {
			throw( type="cbtoon.SyntaxError", message="Expected list item" );
		}
		_cursorAdvance( cursor );
		var content = line.content;
		if ( content == variables.LIST_ITEM_MARKER ) {
			var followDepth = arguments.baseDepth + 1;
			var nextLine = _cursorPeek( cursor );
			if ( isNull( nextLine ) || nextLine.depth < followDepth ) {
				arrayAppend( arguments.events, { type: "startObject" } );
				arrayAppend( arguments.events, { type: "endObject" } );
				return;
			}
			if ( nextLine.depth == followDepth && left( nextLine.content, 2 ) != variables.LIST_ITEM_PREFIX ) {
				arrayAppend( arguments.events, { type: "startObject" } );
				while ( !_cursorAtEnd( cursor ) ) {
					var fieldLine = _cursorPeek( cursor );
					if ( isNull( fieldLine ) || fieldLine.depth < followDepth ) {
						break;
					}
					if ( fieldLine.depth == followDepth && left( fieldLine.content, 2 ) != variables.LIST_ITEM_PREFIX ) {
						_cursorAdvance( cursor );
						_decodeKeyValue( fieldLine.content, cursor, followDepth, arguments.options, arguments.events );
					} else {
						break;
					}
				}
				arrayAppend( arguments.events, { type: "endObject" } );
				return;
			}
			arrayAppend( arguments.events, { type: "startObject" } );
			arrayAppend( arguments.events, { type: "endObject" } );
			return;
		}
		if ( left( content, 2 ) != variables.LIST_ITEM_PREFIX ) {
			throw( type="cbtoon.SyntaxError", message="Expected list item to start with ""#variables.LIST_ITEM_PREFIX#""" );
		}
		var afterHyphen = trim( reReplace( content, "^\- ", "" ) );
		if ( !len( afterHyphen ) ) {
			arrayAppend( arguments.events, { type: "startObject" } );
			arrayAppend( arguments.events, { type: "endObject" } );
			return;
		}
		if ( _isArrayHeaderContent( afterHyphen ) ) {
			var arrayHeader = _parseArrayHeaderLine( afterHyphen, variables.COMMA );
			if ( !structIsEmpty( arrayHeader ) ) {
				_decodeArrayFromHeader( arrayHeader.header, arrayHeader.inlineValues, cursor, arguments.baseDepth, arguments.options, arguments.events );
				return;
			}
		}
		var headerInfo = _parseArrayHeaderLine( afterHyphen, variables.COMMA );
		if ( !structIsEmpty( headerInfo ) && !isNull( headerInfo.header.key ) && len( toString( headerInfo.header.key ) ) && arrayLen( headerInfo.header.fields ) ) {
			var hdr = headerInfo.header;
			arrayAppend( arguments.events, { type: "startObject" } );
			arrayAppend( arguments.events, { type: "key", key: hdr.key } );
			_decodeArrayFromHeader( hdr, headerInfo.inlineValues, cursor, arguments.baseDepth + 1, arguments.options, arguments.events );
			var followDepth = arguments.baseDepth + 1;
			while ( !_cursorAtEnd( cursor ) ) {
				var nextLine2 = _cursorPeek( cursor );
				if ( isNull( nextLine2 ) || nextLine2.depth < followDepth ) {
					break;
				}
				if ( nextLine2.depth == followDepth && left( nextLine2.content, 2 ) != variables.LIST_ITEM_PREFIX ) {
					_cursorAdvance( cursor );
					_decodeKeyValue( nextLine2.content, cursor, followDepth, arguments.options, arguments.events );
				} else {
					break;
				}
			}
			arrayAppend( arguments.events, { type: "endObject" } );
			return;
		}
		if ( _isKeyValueContent( afterHyphen ) ) {
			arrayAppend( arguments.events, { type: "startObject" } );
			_decodeKeyValue( afterHyphen, cursor, arguments.baseDepth + 1, arguments.options, arguments.events );
			var followDepth2 = arguments.baseDepth + 1;
			while ( !_cursorAtEnd( cursor ) ) {
				var nl = _cursorPeek( cursor );
				if ( isNull( nl ) || nl.depth < followDepth2 ) {
					break;
				}
				if ( nl.depth == followDepth2 && left( nl.content, 2 ) != variables.LIST_ITEM_PREFIX ) {
					_cursorAdvance( cursor );
					_decodeKeyValue( nl.content, cursor, followDepth2, arguments.options, arguments.events );
				} else {
					break;
				}
			}
			arrayAppend( arguments.events, { type: "endObject" } );
			return;
		}
		arrayAppend( arguments.events, { type: "primitive", value: _parsePrimitiveToken( afterHyphen ) } );
	}

	private any function _buildValueFromEvents( required array events ) {
		var state = { stack: [], root: JavaCast( "null", "" ) };
		for ( var ei = 1; ei <= arrayLen( arguments.events ); ei++ ) {
			_applyDecodeEvent( state, arguments.events[ ei ] );
		}
		if ( arrayLen( state.stack ) ) {
			throw( type="cbtoon.SyntaxError", message="Incomplete event stream: stack not empty at end" );
		}
		if ( isNull( state.root ) ) {
			throw( type="cbtoon.SyntaxError", message="No root value built from events" );
		}
		return state.root;
	}

	private void function _applyDecodeEvent( required struct state, required struct event ) {
		var stack = arguments.state.stack;
		switch ( arguments.event.type ) {
			case "startObject": {
				var obj = {};
				var ctx = { type: "object", obj: obj, currentKey: JavaCast( "null", "" ) };
				if ( !arrayLen( stack ) ) {
					arrayAppend( stack, ctx );
				} else {
					var parent = stack[ arrayLen( stack ) ];
					if ( parent.type == "object" ) {
						if ( isNull( parent.currentKey ) ) {
							throw( type="cbtoon.SyntaxError", message="Object startObject event without preceding key" );
						}
						parent.obj[ parent.currentKey ] = obj;
						parent.currentKey = JavaCast( "null", "" );
					} else if ( parent.type == "array" ) {
						arrayAppend( parent.arr, obj );
					}
					arrayAppend( stack, ctx );
				}
				break;
			}
			case "endObject": {
				if ( !arrayLen( stack ) ) {
					throw( type="cbtoon.SyntaxError", message="Unexpected endObject event" );
				}
				var popped = stack[ arrayLen( stack ) ];
				arrayDeleteAt( stack, arrayLen( stack ) );
				if ( popped.type != "object" ) {
					throw( type="cbtoon.SyntaxError", message="Mismatched endObject event" );
				}
				if ( !arrayLen( stack ) ) {
					arguments.state.root = popped.obj;
				}
				break;
			}
			case "startArray": {
				var arr = [];
				var actx = { type: "array", arr: arr };
				if ( !arrayLen( stack ) ) {
					arrayAppend( stack, actx );
				} else {
					var parentA = stack[ arrayLen( stack ) ];
					if ( parentA.type == "object" ) {
						if ( isNull( parentA.currentKey ) ) {
							throw( type="cbtoon.SyntaxError", message="Array startArray event without preceding key" );
						}
						parentA.obj[ parentA.currentKey ] = arr;
						parentA.currentKey = JavaCast( "null", "" );
					} else if ( parentA.type == "array" ) {
						arrayAppend( parentA.arr, arr );
					}
					arrayAppend( stack, actx );
				}
				break;
			}
			case "endArray": {
				if ( !arrayLen( stack ) ) {
					throw( type="cbtoon.SyntaxError", message="Unexpected endArray event" );
				}
				var poppedA = stack[ arrayLen( stack ) ];
				arrayDeleteAt( stack, arrayLen( stack ) );
				if ( poppedA.type != "array" ) {
					throw( type="cbtoon.SyntaxError", message="Mismatched endArray event" );
				}
				if ( !arrayLen( stack ) ) {
					arguments.state.root = poppedA.arr;
				}
				break;
			}
			case "key": {
				if ( !arrayLen( stack ) ) {
					throw( type="cbtoon.SyntaxError", message="Key event outside of object context" );
				}
				var parentK = stack[ arrayLen( stack ) ];
				if ( parentK.type != "object" ) {
					throw( type="cbtoon.SyntaxError", message="Key event in non-object context" );
				}
				parentK.currentKey = arguments.event.key;
				break;
			}
			case "primitive": {
				if ( !arrayLen( stack ) ) {
					arguments.state.root = arguments.event.value;
				} else {
					var parentP = stack[ arrayLen( stack ) ];
					if ( parentP.type == "object" ) {
						if ( isNull( parentP.currentKey ) ) {
							throw( type="cbtoon.SyntaxError", message="Primitive event without preceding key in object" );
						}
						parentP.obj[ parentP.currentKey ] = arguments.event.value;
						parentP.currentKey = JavaCast( "null", "" );
					} else if ( parentP.type == "array" ) {
						arrayAppend( parentP.arr, arguments.event.value );
					}
				}
				break;
			}
			default:
				throw( type="cbtoon.SyntaxError", message="Unknown decode event" );
		}
	}

	private boolean function _isIdentifierSegment( required string key ) {
		return reFind( "^[A-Za-z_][A-Za-z0-9_]*$", arguments.key ) == 1;
	}

	private any function _expandPathsSafe( required any value, required boolean strict ) {
		if ( IsArray( arguments.value ) ) {
			var outA = [];
			for ( var i = 1; i <= arrayLen( arguments.value ); i++ ) {
				arrayAppend( outA, _expandPathsSafe( arguments.value[ i ], arguments.strict ) );
			}
			return outA;
		}
		if ( !IsStruct( arguments.value ) ) {
			return arguments.value;
		}
		var expanded = {};
		var expKeys = StructKeyArray( arguments.value );
		for ( var ei = 1; ei <= ArrayLen( expKeys ); ei++ ) {
			var k = expKeys[ ei ];
			if ( _mapEntryNull( arguments.value, k ) ) {
				if ( find( ".", k ) && _isIdentifierSegment( listFirst( k, "." ) ) ) {
					var segmentsN = listToArray( k, "." );
					var allIdN = true;
					for ( var sin = 1; sin <= arrayLen( segmentsN ); sin++ ) {
						if ( !_isIdentifierSegment( segmentsN[ sin ] ) ) {
							allIdN = false;
							break;
						}
					}
					if ( allIdN ) {
						_insertPathSafe( expanded, segmentsN, JavaCast( "null", "" ), arguments.strict );
						continue;
					}
				}
				if ( structKeyExists( expanded, k ) ) {
					if ( arguments.strict ) {
						throw( type="cbtoon.TypeError", message="Path expansion conflict at key ""#k#""" );
					}
				}
				expanded[ k ] = JavaCast( "null", "" );
				continue;
			}
			var expandedChild = _expandPathsSafe( _structEntryPresent( arguments.value, k ), arguments.strict );
			if ( find( ".", k ) && _isIdentifierSegment( listFirst( k, "." ) ) ) {
				var segments = listToArray( k, "." );
				var allId = true;
				for ( var si = 1; si <= arrayLen( segments ); si++ ) {
					if ( !_isIdentifierSegment( segments[ si ] ) ) {
						allId = false;
						break;
					}
				}
				if ( allId ) {
					_insertPathSafe( expanded, segments, expandedChild, arguments.strict );
					continue;
				}
			}
			if ( structKeyExists( expanded, k ) ) {
				if ( arguments.strict ) {
					throw( type="cbtoon.TypeError", message="Path expansion conflict at key ""#k#""" );
				}
			}
			expanded[ k ] = expandedChild;
		}
		return expanded;
	}

	private void function _insertPathSafe( required struct target, required array segments, required any value, required boolean strict ) {
		var node = arguments.target;
		for ( var i = 1; i < arrayLen( arguments.segments ); i++ ) {
			var seg = arguments.segments[ i ];
			if ( !structKeyExists( node, seg ) ) {
				node[ seg ] = {};
			}
			if ( !IsStruct( node[ seg ] ) ) {
				if ( arguments.strict ) {
					throw( type="cbtoon.TypeError", message="Expansion conflict at path ""#seg#""" );
				}
				node[ seg ] = {};
			}
			node = node[ seg ];
		}
		var leaf = arguments.segments[ arrayLen( arguments.segments ) ];
		if ( structKeyExists( node, leaf ) ) {
			if ( arguments.strict && !IsStruct( node[ leaf ] ) ) {
				throw( type="cbtoon.TypeError", message="Expansion conflict at path ""#leaf#""" );
			}
			if ( IsStruct( node[ leaf ] ) && IsStruct( arguments.value ) ) {
				structAppend( node[ leaf ], arguments.value );
				return;
			}
			if ( !arguments.strict ) {
				node[ leaf ] = arguments.value;
				return;
			}
			throw( type="cbtoon.TypeError", message="Expansion conflict at path ""#leaf#""" );
		}
		node[ leaf ] = arguments.value;
	}
}
