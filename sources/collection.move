module dos_collection::collection;

use std::string::String;
use std::type_name::{Self, TypeName};
use sui::coin::{Self, Coin};
use sui::event::emit;
use sui::package::{Self, Publisher};
use sui::table::{Self, Table};
use wal::wal::WAL;
use walrus::blob::Blob;
use walrus::system::System;

//=== Aliases ===

public use fun collection_admin_cap_collection_id as CollectionAdminCap.collection_id;
public use fun collection_admin_cap_destroy as CollectionAdminCap.destroy;

//=== Structs ===

public struct COLLECTION has drop {}

public struct Collection<phantom T> has key, store {
    id: UID,
    state: CollectionState,
    creator: address,
    name: String,
    description: String,
    item_type: TypeName,
    external_url: String,
    image_uri: String,
    items: Table<u64, ID>,
    blobs: Table<u256, Option<Blob>>,
}

public struct CollectionAdminCap<phantom T> has key, store {
    id: UID,
    collection_id: ID,
}

public enum CollectionState has copy, drop, store {
    INITIALIZING { current_supply: u64, target_supply: u64 },
    INITIALIZED { total_supply: u64 },
}

//=== Events ===

public struct CollectionCreatedEvent has copy, drop {
    creator: address,
    collection_id: ID,
    collection_admin_cap_id: ID,
    collection_type: TypeName,
}

//=== Errors ===

const EInvalidPublisher: u64 = 0;
const EInvalidCollectionAdminCap: u64 = 1;
const ECollectionAlreadyInitialized: u64 = 2;
const ECollectionNotInitialized: u64 = 3;
const ECollectionNotInitializing: u64 = 4;

//=== Init Function ===

fun init(otw: COLLECTION, ctx: &mut TxContext) {
    package::claim_and_keep(otw, ctx);
}

//=== Public Functions ===

// Create a new collection.
public fun new<T>(
    publisher: &Publisher,
    name: String,
    creator: address,
    description: String,
    external_url: String,
    image_uri: String,
    target_supply: u64,
    ctx: &mut TxContext,
): (Collection<T>, CollectionAdminCap<T>) {
    assert!(publisher.from_module<T>(), EInvalidPublisher);

    let collection = Collection<T> {
        id: object::new(ctx),
        state: CollectionState::INITIALIZING { current_supply: 0, target_supply: target_supply },
        name: name,
        creator: creator,
        description: description,
        item_type: type_name::get<T>(),
        external_url: external_url,
        image_uri: image_uri,
        items: table::new(ctx),
        blobs: table::new(ctx),
    };

    let collection_admin_cap = CollectionAdminCap {
        id: object::new(ctx),
        collection_id: collection.id.to_inner(),
    };

    emit(CollectionCreatedEvent {
        collection_id: collection.id.to_inner(),
        collection_admin_cap_id: object::id(&collection_admin_cap),
        collection_type: type_name::get<T>(),
        creator: creator,
    });

    (collection, collection_admin_cap)
}

public fun register_item<T: key>(
    self: &mut Collection<T>,
    cap: &CollectionAdminCap<T>,
    number: u64,
    item: &T,
) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);

    match (self.state) {
        CollectionState::INITIALIZING { mut target_supply, .. } => {
            // Assert that the quantity of registered items is less than the target supply.
            assert!(self.items.length() < target_supply, ECollectionAlreadyInitialized);
            // Register the item to the collection.
            self.items.add(number, object::id(item));
            // Increment the target supply.
            target_supply = target_supply + 1;
            // If the quantity of registered items is equal to the target supply, set the state to initialized.
            if (self.items.length() == target_supply) {
                self.state = CollectionState::INITIALIZED { total_supply: target_supply }
            };
        },
        _ => abort ECollectionAlreadyInitialized,
    };
}

// Renew a Blob with a WAL coin. Does not require CollectionAdminCap to allow.
// anyone to renew a Blob associate with this Collection.
public fun renew_blob<T: key>(
    self: &mut Collection<T>,
    blob_id: u256,
    extension_epochs: u32,
    payment_coin: &mut Coin<WAL>,
    system: &mut System,
) {
    let blob_opt_mut = self.blobs.borrow_mut(blob_id);
    let blob_mut = blob_opt_mut.borrow_mut();
    system.extend_blob(blob_mut, extension_epochs, payment_coin);
}

// Reserve a storage slot for a Blob by storing the expected Blob ID mapped to option::none().
public fun reserve_blob<T: key>(
    self: &mut Collection<T>,
    cap: &CollectionAdminCap<T>,
    blob_id: u256,
) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);
    self.blobs.add(blob_id, option::none());
}

// Store a Blob in the Collection, requires a slot to be reserved first.
public fun store_blob<T: key>(self: &mut Collection<T>, cap: &CollectionAdminCap<T>, blob: Blob) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);
    self.blobs.borrow_mut(blob.blob_id()).fill(blob);
}

public fun collection_admin_cap_destroy<T>(cap: CollectionAdminCap<T>) {
    let CollectionAdminCap { id, .. } = cap;
    id.delete();
}

//=== View Functions ===

public fun creator<T>(self: &Collection<T>): address {
    self.creator
}

public fun name<T>(self: &Collection<T>): String {
    self.name
}

public fun description<T>(self: &Collection<T>): String {
    self.description
}

public fun external_url<T>(self: &Collection<T>): String {
    self.external_url
}

public fun image_uri<T>(self: &Collection<T>): String {
    self.image_uri
}

public fun collection_admin_cap_collection_id<T>(cap: &CollectionAdminCap<T>): ID {
    cap.collection_id
}

public fun current_supply<T>(self: &Collection<T>): u64 {
    match (self.state) {
        CollectionState::INITIALIZED { total_supply, .. } => total_supply,
        _ => abort ECollectionNotInitialized,
    }
}

public fun target_supply<T>(self: &Collection<T>): u64 {
    match (self.state) {
        CollectionState::INITIALIZING { target_supply, .. } => target_supply,
        _ => abort ECollectionNotInitializing,
    }
}

public fun total_supply<T>(self: &Collection<T>): u64 {
    match (self.state) {
        CollectionState::INITIALIZED { total_supply, .. } => total_supply,
        _ => abort ECollectionNotInitialized,
    }
}

public fun assert_state_initialized<T>(self: &Collection<T>) {
    match (self.state) {
        CollectionState::INITIALIZED { .. } => (),
        _ => abort ECollectionNotInitialized,
    };
}

public fun assert_state_initializing<T>(self: &Collection<T>) {
    match (self.state) {
        CollectionState::INITIALIZING { .. } => (),
        _ => abort ECollectionNotInitializing,
    };
}
