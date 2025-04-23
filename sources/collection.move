module dos_collection::collection;

use dos_collection::collection_manager::{Self, CollectionManager, CollectionManagerAdminCap};
use dos_collection::collection_metadata::{Self, CollectionMetadata};
use std::string::String;
use sui::dynamic_field as df;
use sui::package::Publisher;

//=== Constants ===

const EInvalidPublisher: u64 = 10000;
const EInvalidCollectionManagerAdminCap: u64 = 10001;
const EInvalidCollectionMetadata: u64 = 10002;

//=== Public Functions ===

// Create a new collection. Creates a CollectionMetadata, CollectionManager, and CollectionManagerAdminCap.
public fun new<T: key>(
    publisher: &Publisher,
    creator: address,
    name: String,
    description: String,
    external_url: String,
    image_uri: String,
    target_supply: u64,
    ctx: &mut TxContext,
): (CollectionMetadata, CollectionManager, CollectionManagerAdminCap) {
    // Assert that the publisher is from the module where `T` is defined.
    assert!(publisher.from_module<T>(), EInvalidPublisher);

    // Create the CollectionMetadata.
    let mut collection_metadata = collection_metadata::new<T>(
        creator,
        name,
        description,
        external_url,
        image_uri,
        ctx,
    );

    // Create the CollectionManager.
    let (mut collection_manager, collection_manager_admin_cap) = collection_manager::new<T>(
        image_uri,
        target_supply,
        ctx,
    );

    // Link the CollectionManager to the CollectionMetadata.
    df::add<vector<u8>, ID>(
        collection_metadata.uid_mut(),
        b"COLLECTION_MANAGER_ID",
        object::id(&collection_manager),
    );

    // Link the CollectionMetadata to the CollectionManager.
    df::add<vector<u8>, ID>(
        collection_manager.uid_mut(),
        b"COLLECTION_METADATA_ID",
        object::id(&collection_metadata),
    );

    (collection_metadata, collection_manager, collection_manager_admin_cap)
}

public fun assert_is_authorized(
    manager_admin_cap: &CollectionManagerAdminCap,
    manager: &CollectionManager,
    metadata: &CollectionMetadata,
) {
    assert!(
        manager_admin_cap.collection_manager_id() == object::id(manager),
        EInvalidCollectionManagerAdminCap,
    );
    assert!(manager.collection_metadata_id() == object::id(metadata), EInvalidCollectionMetadata);
}
