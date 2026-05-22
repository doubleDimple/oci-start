package com.doubledimple.ociserver.service;

import com.doubledimple.dao.entity.CloudSshConn;
import com.doubledimple.dao.entity.CloudSshFolder;
import com.doubledimple.ociserver.pojo.request.CloudSshConnReq;
import com.doubledimple.ocicommon.param.ApiResponse;

import java.util.List;

public interface CloudSshFolderService {

    ApiResponse getFolderTree();

    List<CloudSshConn> findByFolderId(Long id);

    CloudSshFolder createFolder(String name, Long parentId, Integer sortOrder);

    CloudSshFolder updateFolder(Long id, String name, Long parentId, Integer sortOrder);

    void deleteFolder(Long id, boolean force);

    CloudSshConn createInstance(CloudSshConn conn);

    CloudSshConn findInstanceById(Long id);

    CloudSshConn updateInstance(Long id, CloudSshConnReq req);
}
