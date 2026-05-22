package com.doubledimple.dao.repository;

import com.doubledimple.dao.entity.CloudSshFolder;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface CloudSshFolderRepository extends JpaRepository<CloudSshFolder, Long>, JpaSpecificationExecutor<CloudSshFolder> {


    List<CloudSshFolder> findByParentIdAndDeletedFalseOrderBySortOrderAsc(Long parentId);

    @Query("select count(f) from CloudSshFolder f where f.deleted=false and f.parentId=?1 and f.name=?2 and (?3 is null or f.id<>?3)")
    long countByParentAndNameExcludeSelf(Long parentId, String name, Long selfId);
}

