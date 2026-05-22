package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.CloudSshConn;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface CloudSshConnRepository extends JpaRepository<CloudSshConn, Long>, JpaSpecificationExecutor<CloudSshConn> {


    Optional<CloudSshConn> findByInstanceId(String instanceId);

    List<CloudSshConn> findByFolderId(Long folderId);

    long countByFolderId(Long folderId);
    @Modifying
    @Query("update CloudSshConn c set c.folderId=?2 where c.folderId=?1")
    int rebindAllFromFolder(Long fromFolderId, Long toFolderId);   // toFolderId 可为 null

}
