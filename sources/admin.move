module dos_collection::admin;

public struct ADMIN has drop {}

public struct AdminCap has key, store {
    id: UID,
    collection_id: ID,
}
