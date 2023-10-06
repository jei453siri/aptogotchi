module aptogotchi::main {
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::object;
    use aptos_framework::timestamp;
    use aptos_std::string_utils::{to_string};
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    use std::option;
    use std::signer::address_of;
    use std::signer;
    use std::string::{Self, String};
    use std::error;

    /// aptogotchi not available
    const ENOT_AVAILABLE: u64 = 1;

    const HP_UPPER_BOUND: u64 = 10;
    const HAPPINESS_UPPER_BOUND: u64 = 10;

    struct AptoGotchi has key {
        name: String,
        birthday: u64,
        health_points: u64,
        happiness: u64,
        mutator_ref: token::MutatorRef,
        burn_ref: token::BurnRef,
        last_modified_timestamp: u64,
        parts: vector<u8>
    }

    // Tokens require a signer to create, so this is the signer for the collection
    struct CollectionCapability has key, drop {
        capability: SignerCapability,
        burn_signer_capability: SignerCapability,
    }

    const APP_SIGNER_CAPABILITY_SEED: vector<u8> = b"APP_SIGNER_CAPABILITY";
    const BURN_SIGNER_CAPABILITY_SEED: vector<u8> = b"BURN_SIGNER_CAPABILITY";
    const APTOGOTCHI_COLLECTION_NAME: vector<u8> = b"Aptogotchi Collection";
    const APTOGOTCHI_COLLECTION_DESCRIPTION: vector<u8> = b"Aptogotchi Collection Description";
    const APTOGOTCHI_COLLECTION_URI: vector<u8> = b"https://aptogotchi.collection.uri/";

    fun init_module(account: &signer) {
        let (token_resource, token_signer_cap) = account::create_resource_account(
            account,
            APP_SIGNER_CAPABILITY_SEED,
        );
        let (_, burn_signer_capability) = account::create_resource_account(
            account,
            BURN_SIGNER_CAPABILITY_SEED,
        );
        move_to(account, CollectionCapability {
            capability: token_signer_cap,
            burn_signer_capability,
        });

        create_aptogotchi_collection(&token_resource);
    }

    fun get_token_signer(): signer acquires CollectionCapability {
        account::create_signer_with_capability(&borrow_global<CollectionCapability>(@aptogotchi).capability)
    }

    fun create_aptogotchi_collection(creator: &signer) {
        let description = string::utf8(APTOGOTCHI_COLLECTION_DESCRIPTION);
        let name = string::utf8(APTOGOTCHI_COLLECTION_NAME);
        let uri = string::utf8(APTOGOTCHI_COLLECTION_URI);

        collection::create_unlimited_collection(
            creator,
            description,
            name,
            option::none(),
            uri,
        );
    }

    public entry fun create_aptogotchi(user: &signer, name: String, parts: vector<u8>) acquires CollectionCapability {
        let uri = string::utf8(APTOGOTCHI_COLLECTION_URI);
        let description = string::utf8(APTOGOTCHI_COLLECTION_DESCRIPTION);
        let token_name = to_string(&address_of(user));

        let constructor_ref = token::create_named_token(
            &get_token_signer(),
            string::utf8(APTOGOTCHI_COLLECTION_NAME),
            description,
            token_name,
            option::none(),
            uri,
        );

        let token_signer = object::generate_signer(&constructor_ref);
        let mutator_ref = token::generate_mutator_ref(&constructor_ref);
        let burn_ref = token::generate_burn_ref(&constructor_ref);

        let gotchi = AptoGotchi {
            name,
            birthday: timestamp::now_seconds(),
            health_points: HP_UPPER_BOUND,
            happiness: HAPPINESS_UPPER_BOUND,
            mutator_ref,
            burn_ref,
            last_modified_timestamp: timestamp::now_seconds(),
            parts,
        };

        move_to(&token_signer, gotchi);
    }

    fun get_aptogotchi_address(creator_addr: &address): (address) acquires CollectionCapability {
        let collection = string::utf8(APTOGOTCHI_COLLECTION_NAME);
        let token_name = to_string(creator_addr);
        let creator = &get_token_signer();
        let token_address = token::create_token_address(
            &signer::address_of(creator),
            &collection,
            &token_name,
        );

        token_address
    }

    #[view]
    public fun get_name(owner: signer): String acquires AptoGotchi, CollectionCapability {
        let owner_addr = signer::address_of(&owner);
        let token_address = get_aptogotchi_address(&owner_addr);
        let gotchi = borrow_global<AptoGotchi>(token_address);

        gotchi.name
    }

    public entry fun set_name(owner: signer, name: String) acquires AptoGotchi, CollectionCapability {
        let owner_addr = signer::address_of(&owner);
        let token_address = get_aptogotchi_address(&owner_addr);
        let gotchi = borrow_global_mut<AptoGotchi>(token_address);
        gotchi.name = name;

        gotchi.name;
    }

    #[view]
    public fun get_health_points(owner_addr: address): u64 acquires AptoGotchi, CollectionCapability {
        let token_address = get_aptogotchi_address(&owner_addr);
        let gotchi = borrow_global<AptoGotchi>(token_address);

        // get new baseline (calculate how much health_points has decayed)
        let (hp_decay, _) = calculate_decay(gotchi);

        gotchi.health_points - hp_decay
    }

    public entry fun change_health_points(owner_addr: address, hp_difference: u64) acquires AptoGotchi, CollectionCapability {
        let token_address = get_aptogotchi_address(&owner_addr);
        let gotchi = borrow_global_mut<AptoGotchi>(token_address);

        gotchi.health_points = if (gotchi.health_points + hp_difference > HP_UPPER_BOUND) {
            HP_UPPER_BOUND
        } else {
            gotchi.health_points + hp_difference
        };

        let (hp_decay, _) = calculate_decay(gotchi);
        gotchi.health_points = gotchi.health_points - hp_decay;

        gotchi.last_modified_timestamp = timestamp::now_seconds();

        gotchi.health_points;
    }

    #[view]
    public fun get_happiness(owner_addr: address): u64 acquires AptoGotchi, CollectionCapability {
        let token_address = get_aptogotchi_address(&owner_addr);
        let gotchi = borrow_global<AptoGotchi>(token_address);

        // get new baseline
        let (_, happiness_decay) = calculate_decay(gotchi);

        gotchi.happiness - happiness_decay
    }

    public entry fun change_happiness(owner_addr: address, happiness_difference: u64) acquires AptoGotchi, CollectionCapability {
        let token_address = get_aptogotchi_address(&owner_addr);
        let gotchi = borrow_global_mut<AptoGotchi>(token_address);

        gotchi.happiness = if (gotchi.happiness + happiness_difference > HAPPINESS_UPPER_BOUND) {
            HAPPINESS_UPPER_BOUND
        } else {
            gotchi.happiness + happiness_difference
        };

        let (_, happiness_decay) = calculate_decay(gotchi);
        gotchi.happiness = gotchi.happiness - happiness_decay;

        gotchi.last_modified_timestamp = timestamp::now_seconds();

        gotchi.happiness;
    }

    fun calculate_timestamp_diff(gotchi: &AptoGotchi): u64 {
        let current_timestamp = timestamp::now_seconds();
        let timestamp_diff = current_timestamp - gotchi.last_modified_timestamp;
        let timestamp_diff_formatted = timestamp_diff / 60;

        timestamp_diff_formatted
    }

    
    fun calculate_decay(gotchi: &AptoGotchi): (u64, u64) {
        let minutes_passed = calculate_timestamp_diff(gotchi);

        let hp_decay = if (minutes_passed > gotchi.health_points) {
            gotchi.health_points
        } else {
            minutes_passed
        };

        let happiness_decay = if (minutes_passed > gotchi.happiness) {
            gotchi.happiness
        } else {
            minutes_passed
        };

        (hp_decay, happiness_decay)
    }

    #[view]
    public fun get_aptogotchi(owner_addr: address): (String, u64, u64, u64, vector<u8>) acquires AptoGotchi, CollectionCapability {
        let collection = string::utf8(APTOGOTCHI_COLLECTION_NAME);
        let token_name = to_string(&owner_addr);
        let creator = &get_token_signer();
        let token_address = token::create_token_address(
            &signer::address_of(creator),
            &collection,
            &token_name,
        );

        let has_gotchi = exists<AptoGotchi>(token_address);
        assert!(!has_gotchi, error::unavailable(ENOT_AVAILABLE));

        let token_address = get_aptogotchi_address(&owner_addr);
        let gotchi = borrow_global_mut<AptoGotchi>(token_address);

        let (hp_decay, _) = calculate_decay(gotchi);
        gotchi.health_points = gotchi.health_points - hp_decay;

        let (_, happiness_decay) = calculate_decay(gotchi);
        gotchi.happiness = gotchi.happiness - happiness_decay;

        (gotchi.name, gotchi.birthday, gotchi.health_points, gotchi.happiness, gotchi.parts)
    }

    #[view]
    public fun get_parts(owner_addr: address): vector<u8> acquires AptoGotchi, CollectionCapability {
        let token_address = get_aptogotchi_address(&owner_addr);
        let gotchi = borrow_global<AptoGotchi>(token_address);

        gotchi.parts
    }

    public entry fun set_parts(owner: signer, parts: vector<u8>) acquires AptoGotchi, CollectionCapability {
        let owner_addr = signer::address_of(&owner);
        let token_address = get_aptogotchi_address(&owner_addr);
        let gotchi = borrow_global_mut<AptoGotchi>(token_address);
        gotchi.parts = parts;

        gotchi.parts;
    }
}