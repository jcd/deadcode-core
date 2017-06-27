module deadcode.util.plist;

import std.json;
import std.xml;
import std.conv;

import deadcode.test;

// Based on https://github.com/sandofsky/plist-to-json/blob/master/json_to_plist.js
JSONValue plistToJSON(string plistText)
{
	auto doc = new Document(plistText);
 
	static JSONValue jsonify(Element elm)
    {
		switch(elm.tag.name)
        {					
			case "dict", "plist":
				auto childElms = elm.elements;
				auto childElmCount = childElms.length;
				assert ( (childElmCount % 2) == 0 );

                JSONValue[string] d;
				for (int i = 0; i < childElmCount; ++i)
                {
                    assert (childElms[i].tag.name == "key");
	                d[childElms[i].text] = jsonify(childElms[++i]);
                }
                
				return JSONValue(d);
			case "array":
				JSONValue[] arr;
                // arr.capacity = elm.elements.length;
    			foreach (childElm; elm.elements)
	                arr ~= jsonify(childElm);
				return JSONValue(arr);
			case "string":
				return JSONValue(elm.text);
			case "data":
				return JSONValue(elm.text);
			case "real":
				return JSONValue(elm.text.to!float);
			case "integer":
				return JSONValue(elm.text.to!int);
			case "true":
				return JSONValue(true);
			case "false":
				return JSONValue(false);
			default:
	            assert(0);
        }
	}

	foreach (elm; doc.elements)
 		return jsonify(elm);        
    	
    return JSONValue(null);
}


unittest
{
    auto pltxt = q"{
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>fileTypes</key>
	<array>
		<string>ant.xml</string>
		<string>build.xml</string>
	</array>
	<key>firstLineMatch</key>
	<string>&lt;\!--\s*ant\s*--&gt;</string>
	<key>keyEquivalent</key>
	<string>^~A</string>
	<key>name</key>
	<string>Ant</string>
</dict>    
</plist>    
    }";
    
    auto jsontxt = q"{
{                                                
    "fileTypes": [                               
        "ant.xml",                               
        "build.xml"                              
    ],                                           
    "firstLineMatch": "<\\!--\\s*ant\\s*-->",    
    "keyEquivalent": "^~A",                      
    "name": "Ant"                                
}                                                        
    }";
    
    auto plj = plistToJSON(pltxt);
	auto jj = parseJSON(jsontxt);    
	Assert(toJSON(plj, true), toJSON(jj, true));    
//	import std.stdio;
//    writeln(toJSON(plj, true));	
}

