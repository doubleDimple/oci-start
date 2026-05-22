package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.SystemKVStore;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface SystemKVStoreRepository extends JpaRepository<SystemKVStore, Long> {


    Optional<SystemKVStore> findByKey(String key);


}
