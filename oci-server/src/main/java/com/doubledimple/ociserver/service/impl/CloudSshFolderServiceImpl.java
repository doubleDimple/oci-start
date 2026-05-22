package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.CloudSshConn;
import com.doubledimple.dao.entity.CloudSshFolder;
import com.doubledimple.dao.repository.CloudSshConnRepository;
import com.doubledimple.dao.repository.CloudSshFolderRepository;
import com.doubledimple.ociserver.pojo.request.CloudSshConnReq;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.CloudSshFolderService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import java.time.LocalDateTime;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.stream.Collectors;

/**
 * @version 1.0.0
 * @ClassName CloudSshFolderServiceImpl
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-11-07 10:30
 */
@Service
@Slf4j
public class CloudSshFolderServiceImpl implements CloudSshFolderService {

    @Resource
    private CloudSshFolderRepository folderRepo;

    @Resource
    private CloudSshConnRepository cloudSshConnRepository;

    @Override
    public ApiResponse getFolderTree() {
        List<CloudSshFolder> all = folderRepo.findAll()
                .stream()
                .filter(f -> !Boolean.TRUE.equals(f.getDeleted()))
                .collect(Collectors.toList());
        return ApiResponse.success(buildTree(all, null));
    }

    @Override
    public List<CloudSshConn> findByFolderId(Long id) {
        return cloudSshConnRepository.findByFolderId(id);
    }

    @Override
    public CloudSshFolder createFolder(String name, Long parentId, Integer sortOrder) {
        if (name == null || name.trim().isEmpty()) {
            throw new IllegalArgumentException("文件夹名称不能为空");
        }
        // 检查父文件夹是否存在
        if (parentId != null) {
            folderRepo.findById(parentId)
                    .orElseThrow(() -> new IllegalArgumentException("父文件夹不存在"));
        }

        // 重名检查：同一父级下不允许重名
        long count = folderRepo.countByParentAndNameExcludeSelf(parentId, name, null);
        if (count > 0) {
            throw new IllegalArgumentException("同级目录下已存在同名文件夹");
        }

        CloudSshFolder folder = new CloudSshFolder();
        folder.setName(name.trim());
        folder.setParentId(parentId);
        folder.setSortOrder(sortOrder == null ? 0 : sortOrder);
        folder.setCreatedAt(LocalDateTime.now());
        folder.setUpdatedAt(LocalDateTime.now());
        folder.setDeleted(false);

        folderRepo.save(folder);
        return folder;
    }

    @Override
    public CloudSshFolder updateFolder(Long id, String name, Long parentId, Integer sortOrder) {
        CloudSshFolder folder = folderRepo.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("文件夹不存在"));

        if (Boolean.TRUE.equals(folder.getDeleted())) {
            throw new IllegalArgumentException("文件夹已被删除");
        }

        // 若要移动或重命名，需要校验父级及重名
        if (name != null && !name.trim().isEmpty()) {
            long count = folderRepo.countByParentAndNameExcludeSelf(parentId, name, id);
            if (count > 0) {
                throw new IllegalArgumentException("同级目录下已存在同名文件夹");
            }
            folder.setName(name.trim());
        }

        // 移动文件夹：需防止成环（不能移动到自己或其子节点下）
        if (parentId != null && !Objects.equals(folder.getParentId(), parentId)) {
            if (id.equals(parentId)) {
                throw new IllegalArgumentException("不能将文件夹移动到自身下");
            }
            if (isDescendant(id, parentId)) {
                throw new IllegalArgumentException("不能将文件夹移动到其子文件夹下");
            }
            folder.setParentId(parentId);
        }

        if (sortOrder != null) {
            folder.setSortOrder(sortOrder);
        }

        folder.setUpdatedAt(LocalDateTime.now());
        folderRepo.save(folder);
        return folder;
    }

    @Override
    @Transactional
    public void deleteFolder(Long id, boolean force) {
        CloudSshFolder folder = folderRepo.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("文件夹不存在"));

        if (Boolean.TRUE.equals(folder.getDeleted())) {
            throw new IllegalArgumentException("文件夹已被删除");
        }

        List<CloudSshFolder> children = folderRepo.findByParentIdAndDeletedFalseOrderBySortOrderAsc(id);
        long instanceCount = cloudSshConnRepository.countByFolderId(id);

        // 若包含子文件夹或实例，则需判断是否强制删除
        if ((!children.isEmpty() || instanceCount > 0) && !force) {
            throw new IllegalArgumentException("文件夹非空，不能删除（可使用force=true强制删除）");
        }

        // 强制删除：将子文件夹和实例上移到父级
        if (force) {
            Long parentId = folder.getParentId();
            for (CloudSshFolder child : children) {
                child.setParentId(parentId);
                child.setUpdatedAt(LocalDateTime.now());
                folderRepo.save(child);
            }
            cloudSshConnRepository.rebindAllFromFolder(id, parentId);
        }

        // 标记删除
        folder.setDeleted(true);
        folder.setUpdatedAt(LocalDateTime.now());
        folderRepo.save(folder);
    }

    /** 递归判断目标节点是否在源节点的子孙层级中（防止移动成环） */
    private boolean isDescendant(Long sourceId, Long targetParentId) {
        if (targetParentId == null) return false;
        Optional<CloudSshFolder> parentOpt = folderRepo.findById(targetParentId);
        if (!parentOpt.isPresent()) return false;
        CloudSshFolder parent = parentOpt.get();
        if (Objects.equals(parent.getParentId(), sourceId)) return true;
        return isDescendant(sourceId, parent.getParentId());
    }

    private List<Map<String, Object>> buildTree(List<CloudSshFolder> all, Long parentId) {
        return all.stream()
                .filter(f -> Objects.equals(f.getParentId(), parentId))
                .sorted(Comparator.comparing(CloudSshFolder::getSortOrder))
                .map(f -> {
                    Map<String, Object> node = new HashMap<String, Object>();
                    node.put("id", f.getId());
                    node.put("name", f.getName());
                    node.put("children", buildTree(all, f.getId()));
                    return node;
                })
                .collect(Collectors.<Map<String, Object>>toList());
    }

    @Override
    @Transactional
    public CloudSshConn createInstance(CloudSshConn conn) {
        return cloudSshConnRepository.save(conn);
    }

    @Override
    public CloudSshConn findInstanceById(Long id) {
        return cloudSshConnRepository.findById(id)
                .orElse(null);
    }

    @Override
    @Transactional
    public CloudSshConn updateInstance(Long id, CloudSshConnReq req) {
        CloudSshConn conn = cloudSshConnRepository.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("实例不存在"));

        if (req.getFolderId() != null) {
            conn.setFolderId(req.getFolderId());
        }
        if (req.getName() != null) {
            conn.setName(req.getName().trim());
        }
        if (req.getHost() != null) {
            conn.setHost(req.getHost().trim());
        }
        if (req.getPort() != null) {
            conn.setPort(req.getPort());
        }
        if (req.getUsername() != null) {
            conn.setUsername(req.getUsername().trim());
        }
        if (req.getPassword() != null) {
            conn.setPassword(req.getPassword());
        }
        if (req.getRemark() != null) {
            conn.setRemark(req.getRemark().trim());
        }
        return cloudSshConnRepository.save(conn);
    }
}
