package com.acme.billing;

/** Encodes an invoice id for the wire. Shares its BASENAME with
 *  src/main/kotlin/com/acme/util/Codec.kt and nothing else. */
public final class Codec {

    public String encode(String id) {
        return "inv:" + id;
    }
}
