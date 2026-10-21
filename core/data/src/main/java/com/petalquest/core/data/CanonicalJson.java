package com.petalquest.core.data;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;

/** Deterministic app JSON: recursively sorted object keys, compact JSON, original array order. */
final class CanonicalJson {
    static String object(String value) {
        try { return encode(new JSONObject(value)); }
        catch (JSONException e) { throw new IllegalArgumentException("Expected a JSON object", e); }
    }

    private static String encode(Object value) throws JSONException {
        if (value == null || value == JSONObject.NULL) return "null";
        if (value instanceof JSONObject) {
            JSONObject object = (JSONObject)value;
            List<String> keys = new ArrayList<>();
            Iterator<String> iterator = object.keys();
            while (iterator.hasNext()) keys.add(iterator.next());
            Collections.sort(keys);
            StringBuilder result = new StringBuilder("{");
            for (String key : keys) {
                if (result.length() > 1) result.append(',');
                result.append(JSONObject.quote(key)).append(':').append(encode(object.get(key)));
            }
            return result.append('}').toString();
        }
        if (value instanceof JSONArray) {
            JSONArray array = (JSONArray)value;
            StringBuilder result = new StringBuilder("[");
            for (int i=0; i<array.length(); i++) {
                if (i>0) result.append(',');
                result.append(encode(array.get(i)));
            }
            return result.append(']').toString();
        }
        if (value instanceof Number) return JSONObject.numberToString((Number)value);
        if (value instanceof Boolean) return value.toString();
        if (value instanceof String) return JSONObject.quote((String)value);
        throw new IllegalArgumentException("Unsupported JSON value");
    }
}
