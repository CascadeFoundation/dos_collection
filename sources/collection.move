module dos_collection::collection;

use cascade_protocol::mint_cap::MintCap;
use std::string::String;
use std::type_name::{Self, TypeName};
use sui::coin::Coin;
use sui::event::emit;
use sui::package::{Self, Publisher};
use sui::table::{Self, Table};
use sui::transfer::Receiving;
use wal::wal::WAL;
use walrus::blob::Blob;
use walrus::system::System;

//=== Aliases ===

public use fun collection_admin_cap_collection_id as CollectionAdminCap.collection_id;
public use fun collection_admin_cap_destroy as CollectionAdminCap.destroy;

//=== Structs ===

public struct COLLECTION has drop {}

public struct Collection has key, store {
    id: UID,
    item_type: TypeName,
    state: CollectionState,
    creator: address,
    name: String,
    description: String,
    external_url: String,
    image_uri: String,
    items: Table<u64, ID>,
    blobs: Table<u256, Option<Blob>>,
}

public struct CollectionAdminCap has key, store {
    id: UID,
    collection_id: ID,
    item_type: TypeName,
}

public enum CollectionState has copy, drop, store {
    BLOB_RESERVATION { current_supply: u64, target_supply: u64 },
    ITEM_REGISTRATION { current_supply: u64, target_supply: u64 },
    INITIALIZED { total_supply: u64 },
}

//=== Events ===

public struct CollectionCreatedEvent has copy, drop {
    creator: address,
    collection_id: ID,
    collection_admin_cap_id: ID,
    item_type: TypeName,
}

//=== Errors ===

const ENotOneTimeWitness: u64 = 10000;
const EInvalidCollectionAdminCap: u64 = 10001;
const ECollectionAlreadyInitialized: u64 = 10002;
const ECollectionNotInitialized: u64 = 10003;
const EBlobNotReserved: u64 = 10005;
const EInvalidOneTimeWitnessForType: u64 = 10006;
const ETargetSupplyReached: u64 = 20001;
const ENotBlobReservationState: u64 = 20002;
const ENotItemRegistrationState: u64 = 20003;
const ENotInitializedState: u64 = 30000;
const EBlobReservationTargetSupplyNotReached: u64 = 20004;
const EItemRegistrationTargetSupplyNotReached: u64 = 20004;
const EInvalidItemType: u64 = 30001;
const EInvalidPublisher: u64 = 30002;

//=== Init Function ===

fun init(otw: COLLECTION, ctx: &mut TxContext) {
    package::claim_and_keep(otw, ctx);
}

//=== Public Functions ===

// Create a new collection.
public fun new<T: key + store>(
    cap: MintCap<Collection>,
    publisher: &Publisher,
    creator: address,
    name: String,
    description: String,
    external_url: String,
    image_uri: String,
    target_supply: u64,
    ctx: &mut TxContext,
): (Collection, CollectionAdminCap) {
    assert!(publisher.from_module<T>(), EInvalidPublisher);

    let item_type = type_name::get<T>();

    let collection = Collection {
        id: object::new(ctx),
        state: CollectionState::BLOB_RESERVATION {
            current_supply: 0,
            target_supply: target_supply,
        },
        name: name,
        creator: creator,
        description: description,
        item_type: item_type,
        external_url: external_url,
        image_uri: image_uri,
        items: table::new(ctx),
        blobs: table::new(ctx),
    };

    let collection_admin_cap = CollectionAdminCap {
        id: object::new(ctx),
        collection_id: collection.id.to_inner(),
        item_type: item_type,
    };

    emit(CollectionCreatedEvent {
        creator: creator,
        collection_id: collection.id.to_inner(),
        collection_admin_cap_id: object::id(&collection_admin_cap),
        item_type: item_type,
    });

    cap.destroy();

    (collection, collection_admin_cap)
}

public fun register_item<T: key + store>(
    self: &mut Collection,
    cap: &CollectionAdminCap,
    number: u64,
    item: &T,
) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);
    assert!(cap.item_type == type_name::get<T>(), EInvalidItemType);

    match (&mut self.state) {
        CollectionState::ITEM_REGISTRATION { current_supply, target_supply } => {
            // Assert that the quantity of registered items is less than the target supply.
            assert!(self.items.length() < *target_supply, ECollectionAlreadyInitialized);
            // Register the item to the collection.
            self.items.add(number, object::id(item));
            // Set current supply to the new quantity of registered items.
            *current_supply = self.items.length();
        },
        _ => abort ECollectionAlreadyInitialized,
    };
}

public fun unregister_item(self: &mut Collection, cap: &CollectionAdminCap, number: u64) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);

    match (&mut self.state) {
        CollectionState::ITEM_REGISTRATION { current_supply, target_supply } => {
            // Assert that the quantity of registered items is less than the target supply.
            assert!(self.items.length() < *target_supply, ECollectionAlreadyInitialized);
            // Register the item to the collection.
            self.items.remove(number);
            // Set current supply to the new quantity of registered items.
            *current_supply = self.items.length();
        },
        _ => abort ECollectionAlreadyInitialized,
    };
}

// Receive a Blob that's been sent to the Collection, and store it.
public fun receive_and_store_blob(
    self: &mut Collection,
    cap: &CollectionAdminCap,
    blob_to_receive: Receiving<Blob>,
) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);
    let blob = transfer::public_receive(&mut self.id, blob_to_receive);
    internal_store_blob(self, blob);
}

// Renew a Blob with a WAL coin. Does not require CollectionAdminCap to allow for
// anyone to renew a Blob associated with the Collection.
public fun renew_blob(
    self: &mut Collection,
    blob_id: u256,
    extension_epochs: u32,
    payment_coin: &mut Coin<WAL>,
    system: &mut System,
) {
    match (self.state) {
        CollectionState::INITIALIZED { .. } => {
            let blob_opt_mut = self.blobs.borrow_mut(blob_id);
            let blob_mut = blob_opt_mut.borrow_mut();
            system.extend_blob(blob_mut, extension_epochs, payment_coin);
        },
        _ => abort ENotInitializedState,
    };
}

// Store a Blob in the Collection, requires a slot to be reserved first.
// Does not require a CollectionAdminCap because only blobs with the correct digest can be stored.
public fun store_blob(self: &mut Collection, blob: Blob) {
    match (self.state) {
        CollectionState::INITIALIZED { .. } => {
            internal_store_blob(self, blob);
        },
        _ => abort ENotInitializedState,
    };
}

// Swap a Blob with a new Blob, and burn the old one.
public fun swap_blob(self: &mut Collection, blob: Blob) {
    match (self.state) {
        CollectionState::INITIALIZED { .. } => {
            self.blobs.borrow_mut(blob.blob_id()).swap(blob).burn();
        },
        _ => abort ENotInitializedState,
    }
}

// Reserve a storage slot for a Blob by storing the expected Blob ID mapped to option::none().
//
// Required State: BLOB_RESERVATION
public fun reserve_blob_slot(self: &mut Collection, cap: &CollectionAdminCap, blob_id: u256) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);

    match (&mut self.state) {
        CollectionState::BLOB_RESERVATION { current_supply, target_supply } => {
            assert!(*current_supply < *target_supply, ETargetSupplyReached);
            self.blobs.add(blob_id, option::none());
            *current_supply = self.blobs.length();
        },
        _ => abort ECollectionAlreadyInitialized,
    };
}

// Unreserve a Blob slot by removing the Blob ID from the blobs table.
//
// Required State: BLOB_RESERVATION
public fun unreserve_blob_slot(self: &mut Collection, blob_id: u256) {
    match (&mut self.state) {
        CollectionState::BLOB_RESERVATION { current_supply, .. } => {
            self.blobs.remove(blob_id).destroy_none();
            *current_supply = self.blobs.length();
        },
        _ => abort ECollectionAlreadyInitialized,
    };
}

// Destroy a CollectionAdminCap to renounce ownership of the Collection.
// Only callable if the Collection is initialized.
//
// Required State: INITIALIZED
public fun collection_admin_cap_destroy(cap: CollectionAdminCap, self: &mut Collection) {
    match (self.state) {
        CollectionState::INITIALIZED { .. } => {
            let CollectionAdminCap { id, .. } = cap;
            id.delete();
        },
        _ => abort ECollectionNotInitialized,
    };
}

// Transition from BLOB_RESERVATION to ITEM_REGISTRATION state once target supply is reached.
//
// Required State: BLOB_RESERVATION
public fun set_item_registration_state(self: &mut Collection) {
    match (self.state) {
        CollectionState::BLOB_RESERVATION { current_supply, target_supply } => {
            assert!(current_supply == target_supply, EBlobReservationTargetSupplyNotReached);
            self.state = CollectionState::ITEM_REGISTRATION { current_supply, target_supply };
        },
        _ => abort ENotBlobReservationState,
    };
}

// Transition from ITEM_REGISTRATION to INITIALIZED state once target supply is reached.
//
// Required State: ITEM_REGISTRATION
public fun set_initialized_state(self: &mut Collection) {
    match (self.state) {
        CollectionState::ITEM_REGISTRATION { current_supply, target_supply } => {
            assert!(current_supply == target_supply, EItemRegistrationTargetSupplyNotReached);
            self.state = CollectionState::INITIALIZED { total_supply: target_supply };
        },
        _ => abort ENotItemRegistrationState,
    };
}

fun internal_store_blob(self: &mut Collection, blob: Blob) {
    self.blobs.borrow_mut(blob.blob_id()).fill(blob);
}

//=== View Functions ===

public fun creator(self: &Collection): address {
    self.creator
}

public fun description(self: &Collection): String {
    self.description
}

public fun external_url(self: &Collection): String {
    self.external_url
}

public fun image_uri(self: &Collection): String {
    self.image_uri
}

public fun name(self: &Collection): String {
    self.name
}

public fun collection_admin_cap_collection_id(cap: &CollectionAdminCap): ID {
    cap.collection_id
}

public fun current_supply(self: &Collection): u64 {
    match (self.state) {
        CollectionState::BLOB_RESERVATION { current_supply, .. } => current_supply,
        CollectionState::ITEM_REGISTRATION { current_supply, .. } => current_supply,
        _ => abort ECollectionNotInitialized,
    }
}

public fun target_supply(self: &Collection): u64 {
    match (self.state) {
        CollectionState::BLOB_RESERVATION { target_supply, .. } => target_supply,
        CollectionState::ITEM_REGISTRATION { target_supply, .. } => target_supply,
        _ => abort ECollectionNotInitialized,
    }
}

public fun total_supply(self: &Collection): u64 {
    match (self.state) {
        CollectionState::INITIALIZED { total_supply, .. } => total_supply,
        _ => abort ECollectionNotInitialized,
    }
}

public fun assert_blob_reserved(self: &Collection, blob_id: u256) {
    assert!(self.blobs.borrow(blob_id).is_some(), EBlobNotReserved);
}

public fun assert_state_blob_reservation(self: &Collection) {
    match (self.state) {
        CollectionState::BLOB_RESERVATION { .. } => (),
        _ => abort ENotBlobReservationState,
    };
}

public fun assert_state_item_registration(self: &Collection) {
    match (self.state) {
        CollectionState::ITEM_REGISTRATION { .. } => (),
        _ => abort ENotItemRegistrationState,
    };
}

public fun assert_state_initialized(self: &Collection) {
    match (self.state) {
        CollectionState::INITIALIZED { .. } => (),
        _ => abort ENotInitializedState,
    };
}
