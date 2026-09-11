component extends="testbox.system.BaseSpec" {

	function run() {
		var toon = new cbtoon.models.CbToon();

		describe( "CbToon", function() {
			describe( "encodeFromJson", function() {
				it( "should encode struct keys whose value is JSON null without throwing", function() {
					var json = '{"table_number":null,"x":1}';
					var out = toon.encodeFromJson( json );
					expect( out ).toInclude( "table_number" );
					expect( out ).toInclude( "null" );
					expect( out ).toInclude( "x" );
					expect( out ).toInclude( "1" );
				} );

				it( "should encode a simple object to TOON matching the fixture", function() {
					var expected = fileRead( expandPath( "/tests/fixtures/simple-object.toon" ) );
					expected = replace( expected, chr( 13 ), "", "all" );
					var json = '{"name":"Ada","role":"dev","active":true}';
					var out = toon.encodeFromJson( json );
					expect( out ).toBe( trim( expected ) );
				} );

				it( "should encode tabular arrays of objects compactly", function() {
					var json = fileRead( expandPath( "/tests/fixtures/hikes.json" ) );
					var out = toon.encodeFromJson( json );
					expect( out ).toInclude( "friends[3]:" );
					expect( out ).toInclude( "hikes[2]{" );
					expect( out ).toInclude( "Blue Lake Trail" );
				} );

				it( "should encode list-style objects when a rest key is JSON null (Sentry MIS-4JJ trends)", function() {
					var json = fileRead( expandPath( "/tests/fixtures/null-in-list-objects.json" ) );
					var out = toon.encodeFromJson( json );
					expect( out ).toInclude( "trends" );
					expect( out ).toInclude( "null" );
					expect( out ).toInclude( "label" );
				} );

				it( "should encode tabular rows with null cells", function() {
					var json = fileRead( expandPath( "/tests/fixtures/null-tabular-cells.json" ) );
					var out = toon.encodeFromJson( json );
					expect( reFind( "rows\[2\]\{(name,score|score,name)\}:", out ) ).toBeGT( 0 );
					expect( out ).toInclude( "null" );
					expect( out ).toInclude( "Ada" );
					expect( out ).toInclude( "10" );
				} );

				it( "should encode arrays containing JSON null elements", function() {
					var json = fileRead( expandPath( "/tests/fixtures/null-array-elements.json" ) );
					var out = toon.encodeFromJson( json );
					expect( out ).toInclude( "values[3]:" );
					expect( out ).toInclude( "null" );
				} );
			} );

			describe( "encodeFromCfml", function() {
				it( "should encode structs and arrays like JSON", function() {
					var data = { "x": 1, "y": [ 1, 2, 3 ] };
					var out = toon.encodeFromCfml( data );
					expect( out ).toInclude( "x: 1" );
					expect( out ).toInclude( "y[3]:" );
				} );

				it( "should encode a nested query as tabular TOON using query column order", function() {
					var q = queryNew( "id,name", "integer,varchar", [
						[ 1, "Alice" ],
						[ 2, "Bob" ]
					] );
					var out = toon.encodeFromCfml( { "users": q } );
					expect( out ).toInclude( "users[2]{id,name}:" );
					expect( out ).toInclude( "Alice" );
					expect( out ).toInclude( "Bob" );
				} );

				it( "should encode a top-level query as tabular TOON", function() {
					var q = queryNew( "id,name", "integer,varchar", [
						[ 1, "Ada" ]
					] );
					var out = toon.encodeFromCfml( q );
					expect( out ).toInclude( "[1]{id,name}:" );
					expect( out ).toInclude( "Ada" );
				} );

				it( "should encode an empty query with columns as a zero-length tabular header", function() {
					var q = queryNew( "id,name", "integer,varchar", [] );
					var out = toon.encodeFromCfml( q );
					expect( out ).toBe( "[0]{id,name}:" );
				} );

				it( "should encode a query nested in an array as a tabular list item", function() {
					var q = queryNew( "n", "integer", [ [ 7 ] ] );
					var out = toon.encodeFromCfml( [ q ] );
					expect( out ).toInclude( "[1]{n}:" );
					expect( out ).toInclude( "7" );
				} );

				it( "should encode Jira-style ISO date strings on struct fields rather than dropping them", function() {
					var data = {
						  "created"        : "2026-07-01T10:15:04.000+0100"
						, "resolutiondate" : "2026-07-01T17:03:38.000+0100"
						, "status"         : "Done"
					};
					var out = toon.encodeFromCfml( data );
					expect( out ).toInclude( "created:" );
					expect( out ).toInclude( "resolutiondate:" );
					expect( reFind( "created:\s+""2026-07-01T", out ) ).toBeGT( 0 );
					expect( reFind( "resolutiondate:\s+""2026-07-01T", out ) ).toBeGT( 0 );
					expect( out ).toInclude( "status: Done" );
				} );

				it( "should encode CFML date objects on struct fields rather than dropping them", function() {
					var data = {
						  "created" : CreateDateTime( 2026, 7, 1, 10, 15, 4 )
						, "status"  : "Done"
					};
					var out = toon.encodeFromCfml( data );
					expect( out ).toInclude( "created:" );
					expect( reFind( "created:\s+\S+", out ) ).toBeGT( 0 );
					expect( out ).toInclude( "status: Done" );
				} );

				it( "should still encode null date fields as null", function() {
					var out = toon.encodeFromJson( '{"resolutiondate":null,"status":"Open"}' );
					expect( out ).toInclude( "resolutiondate: null" );
					expect( out ).toInclude( "status: Open" );
				} );
			} );

			describe( "decodeToCfml", function() {
				it( "should decode a single-element primitive inline array as a number", function() {
					var s = toon.decodeToCfml( "test[1]: 1" );
					expect( s.test[ 1 ] ).toBeNumeric();
					expect( s.test[ 1 ] ).toBe( 1 );
				} );

				it( "should decode TOON fixture to a struct", function() {
					var raw = fileRead( expandPath( "/tests/fixtures/simple-object.toon" ) );
					var s = toon.decodeToCfml( raw );
					expect( s ).toBeStruct();
					expect( s.name ).toBe( "Ada" );
					expect( s.role ).toBe( "dev" );
					expect( s.active ).toBeTrue();
				} );

				it( "should decode inline primitive arrays", function() {
					var s = toon.decodeToCfml( "tags[3]: admin,ops,dev" );
					expect( s.tags ).toBeArray();
					expect( arrayLen( s.tags ) ).toBe( 3 );
					expect( s.tags[ 1 ] ).toBe( "admin" );
				} );

				it( "should decode tabular arrays to arrays of structs", function() {
					var t = "users[2]{id,name,active}:" & chr( 10 )
						& "  1,Alice,true" & chr( 10 )
						& "  2,Bob,false";
					var s = toon.decodeToCfml( t );
					expect( s.users ).toBeArray();
					expect( s.users[ 1 ].id ).toBe( 1 );
					expect( s.users[ 1 ].name ).toBe( "Alice" );
					expect( s.users[ 2 ].active ).toBeFalse();
				} );
			} );

			describe( "decodeToJson", function() {
				it( "should return JSON string for decoded TOON", function() {
					var raw = fileRead( expandPath( "/tests/fixtures/simple-object.toon" ) );
					var j = toon.decodeToJson( raw );
					expect( isJson( j ) ).toBeTrue();
					var o = DeserializeJSON( j );
					expect( o.name ).toBe( "Ada" );
				} );

				it( "should honour expandPaths safe when emitting JSON", function() {
					var raw = fileRead( expandPath( "/tests/fixtures/expand-paths-flat.toon" ) );
					var j = toon.decodeToJson( raw, { expandPaths: "safe" } );
					expect( isJson( j ) ).toBeTrue();
					var o = DeserializeJSON( j );
					expect( o.meta.version ).toBe( 1 );
					expect( o.a.b.c ).toBe( 42 );
					expect( arrayLen( o.seq ) ).toBe( 3 );
				} );
			} );

			describe( "decode expandPaths safe", function() {
				var safeOpts = { expandPaths: "safe", strict: true, indent: 2 };

				it( "should leave dotted keys flat when expandPaths is off", function() {
					var raw = fileRead( expandPath( "/tests/fixtures/expand-paths-flat.toon" ) );
					var s = toon.decodeToCfml( raw, {} );
					expect( structKeyExists( s, "meta.version" ) ).toBeTrue();
					expect( structKeyExists( s, "meta" ) ).toBeFalse();
				} );

				it( "should expand dotted keys into nested structs and null leaves", function() {
					var raw = fileRead( expandPath( "/tests/fixtures/expand-paths-flat.toon" ) );
					var s = toon.decodeToCfml( raw, safeOpts );
					expect( structKeyExists( s, "meta.version" ) ).toBeFalse();
					expect( s.meta.version ).toBe( 1 );
					expect( IsNull( s.meta.trends ) ).toBeTrue();
					expect( s.a.b.c ).toBe( 42 );
					expect( IsNull( s.plain ) ).toBeTrue();
					expect( arrayLen( s.seq ) ).toBe( 3 );
					expect( s.seq[ 1 ] ).toBe( 1 );
					expect( IsNull( s.seq[ 2 ] ) ).toBeTrue();
					expect( s.seq[ 3 ] ).toBe( 3 );
				} );

				it( "should expand dotted keys under nested objects", function() {
					var raw = fileRead( expandPath( "/tests/fixtures/expand-paths-nested.toon" ) );
					var s = toon.decodeToCfml( raw, safeOpts );
					expect( s.outer.child.value ).toBe( 1 );
					expect( IsNull( s.outer.child.flag ) ).toBeTrue();
					expect( arrayLen( s.tags ) ).toBe( 2 );
					expect( s.tags[ 1 ] ).toBe( "alpha" );
				} );

				it( "should expand dotted column names inside tabular row structs", function() {
					var raw = fileRead( expandPath( "/tests/fixtures/expand-paths-tabular.toon" ) );
					var s = toon.decodeToCfml( raw, safeOpts );
					expect( arrayLen( s.rows ) ).toBe( 2 );
					expect( s.rows[ 1 ].id ).toBe( 1 );
					expect( s.rows[ 1 ].meta.label ).toBe( "one" );
					expect( s.rows[ 2 ].meta.label ).toBe( "two" );
				} );

				it( "should expand dotted keys alongside inline primitive arrays containing nulls", function() {
					var raw = fileRead( expandPath( "/tests/fixtures/expand-paths-inline-null.toon" ) );
					var s = toon.decodeToCfml( raw, safeOpts );
					expect( IsNull( s.meta.flags ) ).toBeTrue();
					expect( s.meta.ok ).toBeTrue();
					expect( arrayLen( s.data.row ) ).toBe( 3 );
					expect( s.data.row[ 1 ] ).toBe( 1 );
					expect( IsNull( s.data.row[ 2 ] ) ).toBeTrue();
					expect( s.data.row[ 3 ] ).toBe( 3 );
				} );

				it( "should throw cbtoon.TypeError when strict expansion collides with a scalar path segment", function() {
					var raw = fileRead( expandPath( "/tests/fixtures/expand-paths-strict-conflict.toon" ) );
					var threw = false;
					try {
						toon.decodeToCfml( raw, safeOpts );
					} catch ( any e ) {
						threw = true;
						expect( e.type ).toBe( "cbtoon.TypeError" );
					}
					expect( threw ).toBeTrue();
				} );

				it( "should match defaultDecodeOptions expandPaths off", function() {
					expect( toon.defaultDecodeOptions().expandPaths ).toBe( "off" );
				} );
			} );

			describe( "round-trip", function() {
				it( "should preserve hikes data when decoding encoded TOON", function() {
					var json = fileRead( expandPath( "/tests/fixtures/hikes.json" ) );
					var mid = toon.encodeFromJson( json );
					var cf = toon.decodeToCfml( mid );
					expect( arrayLen( cf.hikes ) ).toBe( 2 );
					expect( cf.hikes[ 1 ].name ).toBe( "Blue Lake Trail" );
					expect( cf.hikes[ 1 ].distanceKm ).toBeNumeric();
					expect( cf.hikes[ 1 ].wasSunny ).toBeBoolean();
					expect( cf.friends[ 2 ] ).toBe( "luis" );
				} );

				it( "should round-trip mixed arrays as stable TOON text", function() {
					var json = fileRead( expandPath( "/tests/fixtures/mixed-array.json" ) );
					var mid = toon.encodeFromJson( json );
					var again = toon.encodeFromCfml( toon.decodeToCfml( mid ) );
					expect( again ).toBe( mid );
				} );

				it( "should round-trip list primitive 1 when the value is a Java integer", function() {
					var mid = toon.encodeFromCfml( { "items": [ JavaCast( "int", 1 ) ] } );
					var cf = toon.decodeToCfml( mid );
					expect( cf.items[ 1 ] ).toBeNumeric();
					expect( cf.items[ 1 ] ).toBe( 1 );
				} );

				it( "should round-trip expandPaths safe flat fixture via encode then decode", function() {
					var raw = fileRead( expandPath( "/tests/fixtures/expand-paths-flat.toon" ) );
					var safeOpts = { expandPaths: "safe", strict: true, indent: 2 };
					var s1 = toon.decodeToCfml( raw, safeOpts );
					var mid = toon.encodeFromCfml( s1 );
					var s2 = toon.decodeToCfml( mid, safeOpts );
					expect( s2.meta.version ).toBe( s1.meta.version );
					expect( IsNull( s2.meta.trends ) ).toBeTrue();
					expect( s2.a.b.c ).toBe( s1.a.b.c );
					expect( IsNull( s2.plain ) ).toBeTrue();
					expect( arrayLen( s2.seq ) ).toBe( 3 );
					expect( s2.seq[ 1 ] ).toBe( 1 );
					expect( IsNull( s2.seq[ 2 ] ) ).toBeTrue();
					expect( s2.seq[ 3 ] ).toBe( 3 );
				} );

				it( "should round-trip expandPaths safe nested fixture", function() {
					var raw = fileRead( expandPath( "/tests/fixtures/expand-paths-nested.toon" ) );
					var safeOpts = { expandPaths: "safe", strict: true, indent: 2 };
					var s1 = toon.decodeToCfml( raw, safeOpts );
					var mid = toon.encodeFromCfml( s1 );
					var s2 = toon.decodeToCfml( mid, safeOpts );
					expect( s2.outer.child.value ).toBe( 1 );
					expect( IsNull( s2.outer.child.flag ) ).toBeTrue();
					expect( arrayLen( s2.tags ) ).toBe( 2 );
				} );

				it( "should round-trip expandPaths safe tabular rows with dotted columns", function() {
					var raw = fileRead( expandPath( "/tests/fixtures/expand-paths-tabular.toon" ) );
					var safeOpts = { expandPaths: "safe", strict: true, indent: 2 };
					var s1 = toon.decodeToCfml( raw, safeOpts );
					var mid = toon.encodeFromCfml( s1 );
					var s2 = toon.decodeToCfml( mid, safeOpts );
					expect( arrayLen( s2.rows ) ).toBe( 2 );
					expect( s2.rows[ 1 ].meta.label ).toBe( "one" );
					expect( s2.rows[ 2 ].meta.label ).toBe( "two" );
				} );

				it( "should round-trip null-heavy JSON with expandPaths safe on decode", function() {
					var json = fileRead( expandPath( "/tests/fixtures/null-in-list-objects.json" ) );
					var safeOpts = { expandPaths: "safe", strict: true, indent: 2 };
					var mid = toon.encodeFromJson( json );
					var s1 = toon.decodeToCfml( mid, safeOpts );
					var mid2 = toon.encodeFromCfml( s1 );
					var s2 = toon.decodeToCfml( mid2, safeOpts );
					expect( arrayLen( s2 ) ).toBe( 2 );
					expect( IsNull( s2[ 1 ].trends ) ).toBeTrue();
					expect( s2[ 2 ].label ).toBe( "b" );
				} );

				it( "should round-trip expandPaths safe inline-null fixture", function() {
					var raw = fileRead( expandPath( "/tests/fixtures/expand-paths-inline-null.toon" ) );
					var safeOpts = { expandPaths: "safe", strict: true, indent: 2 };
					var s1 = toon.decodeToCfml( raw, safeOpts );
					var mid = toon.encodeFromCfml( s1 );
					var s2 = toon.decodeToCfml( mid, safeOpts );
					expect( IsNull( s2.meta.flags ) ).toBeTrue();
					expect( s2.meta.ok ).toBeTrue();
					expect( arrayLen( s2.data.row ) ).toBe( 3 );
					expect( s2.data.row[ 1 ] ).toBe( 1 );
					expect( IsNull( s2.data.row[ 2 ] ) ).toBeTrue();
					expect( s2.data.row[ 3 ] ).toBe( 3 );
				} );
			} );
		} );
	}

}
