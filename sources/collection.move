module dos_collection::collection;

use std::string::String;
use std::type_name::{Self, TypeName};
use sui::coin::Coin;
use sui::display;
use sui::event::emit;
use sui::package::{Self, Publisher};
use sui::table::{Self, Table};
use sui::transfer::Receiving;
use wal::wal::WAL;
use walrus::blob::Blob;
use walrus::storage_resource::Storage;
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
    total_supply: u64,
    items: Table<u64, ID>,
    blobs: Table<u256, Option<Blob>>,
}

public struct CollectionAdminCap has key, store {
    id: UID,
    collection_id: ID,
    item_type: TypeName,
}

public enum CollectionState has copy, drop, store {
    ITEM_REGISTRATION { registered_count: u64 },
    INITIALIZED,
}

//=== Events ===

public struct CollectionBlobExtendedWithWalEvent has copy, drop {
    collection_id: ID,
    blob_id: u256,
    extension_epochs: u32,
}

public struct CollectionBlobExtendedWithStorageEvent has copy, drop {
    collection_id: ID,
    blob_id: u256,
    start_epoch: u32,
    end_epoch: u32,
}

public struct CollectionCreatedEvent has copy, drop {
    creator: address,
    collection_id: ID,
    collection_admin_cap_id: ID,
    item_type: TypeName,
}

public struct CollectionItemRegisteredEvent has copy, drop {
    collection_id: ID,
    item_id: ID,
    item_number: u64,
}

public struct CollectionItemUnregisteredEvent has copy, drop {
    collection_id: ID,
    item_id: ID,
    item_number: u64,
}

public struct CollectionBlobStoredEvent has copy, drop {
    collection_id: ID,
    blob_id: u256,
}

public struct CollectionBlobSwappedEvent has copy, drop {
    collection_id: ID,
    blob_id: u256,
}

public struct CollectionBlobSlotReservedEvent has copy, drop {
    collection_id: ID,
    blob_id: u256,
}

public struct CollectionBlobSlotsReservedEvent has copy, drop {
    collection_id: ID,
    blob_ids: vector<u256>,
}

public struct CollectionBlobSlotUnreservedEvent has copy, drop {
    collection_id: ID,
    blob_id: u256,
}

//=== Errors ===

const EInvalidCollectionAdminCap: u64 = 10001;
const ECollectionAlreadyInitialized: u64 = 10002;
const ECollectionNotInitialized: u64 = 10003;
const ENotItemRegistrationState: u64 = 20001;
const EItemRegistrationTargetSupplyNotReached: u64 = 20002;
const ENotInitializedState: u64 = 30001;
const EInvalidItemType: u64 = 30002;
const EInvalidPublisher: u64 = 30003;
const EBlobNotReserved: u64 = 40001;
const EBlobNotStored: u64 = 40002;

//=== Init Function ===

fun init(otw: COLLECTION, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    let mut display = display::new<Collection>(&publisher, ctx);
    display.add(b"item_type".to_string(), b"{item_type}".to_string());
    display.add(b"creator".to_string(), b"{creator}".to_string());
    display.add(b"name".to_string(), b"{name}".to_string());
    display.add(b"description".to_string(), b"{description}".to_string());
    display.add(b"external_url".to_string(), b"{external_url}".to_string());
    display.add(b"image_uri".to_string(), b"{image_uri}".to_string());

    transfer::public_transfer(display, ctx.sender());
    transfer::public_transfer(publisher, ctx.sender());
}

//=== Public Functions ===

// Create a new collection.
public fun new<T: key + store>(
    publisher: &Publisher,
    creator: address,
    name: String,
    description: String,
    external_url: String,
    image_uri: String,
    total_supply: u64,
    ctx: &mut TxContext,
): (Collection, CollectionAdminCap) {
    assert!(publisher.from_module<T>(), EInvalidPublisher);

    let item_type = type_name::get<T>();

    let collection = Collection {
        id: object::new(ctx),
        state: CollectionState::ITEM_REGISTRATION { registered_count: 0 },
        name: name,
        creator: creator,
        description: description,
        item_type: item_type,
        external_url: external_url,
        image_uri: image_uri,
        total_supply: total_supply,
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
        CollectionState::ITEM_REGISTRATION { registered_count } => {
            // Assert that the quantity of registered items is less than the target supply.
            assert!(self.items.length() < self.total_supply, ECollectionAlreadyInitialized);
            // Register the item to the collection.
            self.items.add(number, object::id(item));
            // Set current supply to the new quantity of registered items.
            *registered_count = self.items.length();

            emit(CollectionItemRegisteredEvent {
                collection_id: self.id.to_inner(),
                item_id: object::id(item),
                item_number: number,
            });
        },
        _ => abort ECollectionAlreadyInitialized,
    };
}

public fun unregister_item(self: &mut Collection, cap: &CollectionAdminCap, number: u64) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);

    match (&mut self.state) {
        CollectionState::ITEM_REGISTRATION { registered_count } => {
            // Assert that the quantity of registered items is less than the target supply.
            assert!(self.items.length() < self.total_supply, ECollectionAlreadyInitialized);
            // Register the item to the collection.
            let item_id = self.items.remove(number);
            // Set current supply to the new quantity of registered items.
            *registered_count = self.items.length();

            emit(CollectionItemUnregisteredEvent {
                collection_id: self.id.to_inner(),
                item_id: item_id,
                item_number: number,
            });
        },
        _ => abort ECollectionAlreadyInitialized,
    };
}

// Receive a blob that's been sent to the Collection, and store it.
public fun receive_and_store_blob(self: &mut Collection, blob_to_receive: Receiving<Blob>) {
    let blob = transfer::public_receive(&mut self.id, blob_to_receive);
    internal_store_blob(self, blob);
}

// Receive and store blobs that have been sent to the Collection, and store them.
public fun receive_and_store_blobs(
    self: &mut Collection,
    blobs_to_receive: vector<Receiving<Blob>>,
) {
    blobs_to_receive.destroy!(|blob_to_receive| receive_and_store_blob(self, blob_to_receive));
}

// Renew a Blob with a WAL coin. Does not require CollectionAdminCap to allow for
// anyone to renew a Blob associated with the Collection.
public fun extend_blob_with_wal(
    self: &mut Collection,
    blob_id: u256,
    extension_epochs: u32,
    payment_coin: &mut Coin<WAL>,
    system: &mut System,
) {
    let blob_mut = self.blobs.borrow_mut(blob_id).borrow_mut();

    system.extend_blob(blob_mut, extension_epochs, payment_coin);

    emit(CollectionBlobExtendedWithWalEvent {
        collection_id: self.id.to_inner(),
        blob_id: blob_id,
        extension_epochs: extension_epochs,
    });
}

// Renew a Blob with a Storage resource. Does not require CollectionAdminCap to allow for
// anyone to renew a Blob associated with the Collection.
public fun extend_blob_with_storage(
    self: &mut Collection,
    blob_id: u256,
    storage: Storage,
    system: &mut System,
) {
    let blob_mut = self.blobs.borrow_mut(blob_id).borrow_mut();

    emit(CollectionBlobExtendedWithStorageEvent {
        collection_id: self.id.to_inner(),
        blob_id: blob_id,
        start_epoch: storage.start_epoch(),
        end_epoch: storage.end_epoch(),
    });

    system.extend_blob_with_resource(blob_mut, storage);
}

// Store a Blob in the Collection, requires a slot to be reserved first.
// Does not require a CollectionAdminCap because only blobs with the correct digest can be stored.
public fun store_blob(self: &mut Collection, blob: Blob) {
    internal_store_blob(self, blob);
}

// Swap a Blob with a new Blob, and burn the old one.
public fun swap_blob(self: &mut Collection, blob: Blob) {
    emit(CollectionBlobSwappedEvent {
        collection_id: self.id.to_inner(),
        blob_id: blob.blob_id(),
    });
    self.blobs.borrow_mut(blob.blob_id()).swap(blob).burn();
}

// Reserve a storage slot for a Blob by storing the expected Blob ID mapped to option::none().
//
// Required State: BLOB_RESERVATION
#[allow(unused_assignment)]
public fun reserve_blob_slot(self: &mut Collection, cap: &CollectionAdminCap, blob_id: u256) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);
    self.internal_reserve_blob_slot(blob_id);
}

#[allow(unused_assignment)]
public fun reserve_blob_slots(
    self: &mut Collection,
    cap: &CollectionAdminCap,
    blob_ids: vector<u256>,
) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);
    blob_ids.destroy!(|blob_id| self.internal_reserve_blob_slot(blob_id));
    emit(CollectionBlobSlotsReservedEvent {
        collection_id: self.id.to_inner(),
        blob_ids: blob_ids,
    });
}

// Unreserve a Blob slot by removing the Blob ID from the blobs table.
//
// Required State: BLOB_RESERVATION
public fun unreserve_blob_slot(self: &mut Collection, blob_id: u256) {
    self.blobs.remove(blob_id).destroy_none();
    emit(CollectionBlobSlotUnreservedEvent {
        collection_id: self.id.to_inner(),
        blob_id: blob_id,
    });
}

// Destroy a CollectionAdminCap to renounce ownership of the Collection.
// Only callable if the Collection is initialized.
//
// Required State: INITIALIZED
public fun collection_admin_cap_destroy(cap: CollectionAdminCap, self: &mut Collection) {
    match (self.state) {
        CollectionState::INITIALIZED => {
            let CollectionAdminCap { id, .. } = cap;
            id.delete();
        },
        _ => abort ECollectionNotInitialized,
    };
}

// Transition from ITEM_REGISTRATION to INITIALIZED state once target supply is reached.
//
// Required State: ITEM_REGISTRATION
public fun set_initialized_state(self: &mut Collection) {
    match (self.state) {
        CollectionState::ITEM_REGISTRATION { registered_count } => {
            assert!(registered_count == self.total_supply, EItemRegistrationTargetSupplyNotReached);
            self.state = CollectionState::INITIALIZED;
        },
        _ => abort ENotItemRegistrationState,
    };
}

fun internal_reserve_blob_slot(self: &mut Collection, blob_id: u256) {
    self.blobs.add(blob_id, option::none());
    emit(CollectionBlobSlotReservedEvent {
        collection_id: self.id.to_inner(),
        blob_id: blob_id,
    });
}

fun internal_store_blob(self: &mut Collection, blob: Blob) {
    emit(CollectionBlobStoredEvent {
        collection_id: self.id.to_inner(),
        blob_id: blob.blob_id(),
    });
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

public fun registered_count(self: &Collection): u64 {
    match (self.state) {
        CollectionState::ITEM_REGISTRATION { registered_count, .. } => registered_count,
        _ => abort ECollectionNotInitialized,
    }
}

public fun total_supply(self: &Collection): u64 {
    self.total_supply
}

//=== Assert Functions ===

public fun assert_blob_reserved(self: &Collection, blob_id: u256) {
    assert!(self.blobs.contains(blob_id), EBlobNotReserved);
}

public fun assert_blob_stored(self: &Collection, blob_id: u256) {
    assert!(self.blobs.borrow(blob_id).is_some(), EBlobNotStored);
}

public fun assert_state_item_registration(self: &Collection) {
    match (self.state) {
        CollectionState::ITEM_REGISTRATION { .. } => (),
        _ => abort ENotItemRegistrationState,
    };
}

public fun assert_state_initialized(self: &Collection) {
    match (self.state) {
        CollectionState::INITIALIZED => (),
        _ => abort ENotInitializedState,
    };
}

// Assert that a CollectionAdminCap is valid for the Collection.
public fun assert_valid_collection_admin_cap(self: &Collection, cap: &CollectionAdminCap) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);
}
