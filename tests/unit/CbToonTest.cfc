component extends="testbox.system.BaseSpec" {

	function run() {
		var toon = new cbtoon.models.CbToon();

		describe( "CbToon", function() {
			describe( "encodeFromJson", function() {
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
			} );
		} );
	}

}
