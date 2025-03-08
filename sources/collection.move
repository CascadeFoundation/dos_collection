module dos_collection::collection;

use std::string::String;
use std::type_name::{Self, TypeName};
use sui::package::{Self, Publisher};
use sui::url::Url;

//=== Aliases ===

public use fun collection_admin_cap_collection_id as CollectionAdminCap.collection_id;
public use fun collection_admin_cap_id as CollectionAdminCap.id;

//=== Structs ===

public struct COLLECTION has drop {}

public struct Collection<phantom T> has key, store {
    id: UID,
    creator: address,
    name: String,
    description: String,
    item_type: TypeName,
    external_url: Url,
    image_uri: String,
    supply: u64,
}

public struct CollectionAdminCap<phantom T> has key, store {
    id: UID,
    collection_id: ID,
}

//=== Errors ===

const EInvalidPublisher: u64 = 0;

//=== Init Function ===

fun init(otw: COLLECTION, ctx: &mut TxContext) {
    package::claim_and_keep(otw, ctx);
}

//=== Public Functions ===

public fun new<T>(
    publisher: &Publisher,
    name: String,
    creator: address,
    description: String,
    external_url: Url,
    image_uri: String,
    supply: u64,
    ctx: &mut TxContext,
): (Collection<T>, CollectionAdminCap<T>) {
    assert!(publisher.from_module<T>() == true, EInvalidPublisher);

    let collection = Collection<T> {
        id: object::new(ctx),
        name: name,
        creator: creator,
        description: description,
        item_type: type_name::get<T>(),
        external_url: external_url,
        image_uri: image_uri,
        supply: supply,
    };

    let collection_admin_cap = CollectionAdminCap {
        id: object::new(ctx),
        collection_id: collection.id(),
    };

    (collection, collection_admin_cap)
}

//=== View Functions ===

public fun id<T>(self: &Collection<T>): ID {
    self.id.to_inner()
}

public fun creator<T>(self: &Collection<T>): address {
    self.creator
}

public fun name<T>(self: &Collection<T>): String {
    self.name
}

public fun description<T>(self: &Collection<T>): String {
    self.description
}

public fun external_url<T>(self: &Collection<T>): &Url {
    &self.external_url
}

public fun image_uri<T>(self: &Collection<T>): String {
    self.image_uri
}

public fun supply<T>(self: &Collection<T>): u64 {
    self.supply
}

public fun collection_admin_cap_collection_id<T>(cap: &CollectionAdminCap<T>): ID {
    cap.collection_id
}

public fun collection_admin_cap_id<T>(cap: &CollectionAdminCap<T>): ID {
    cap.id.to_inner()
}
