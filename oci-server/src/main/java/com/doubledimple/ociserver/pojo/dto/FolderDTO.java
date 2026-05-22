package com.doubledimple.ociserver.pojo.dto;

import com.doubledimple.dao.entity.CloudSshFolder;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class FolderDTO {
    private Long id;
    private String name;
    private Long parentId;
    private Integer sortOrder;

    public static FolderDTO from(CloudSshFolder f) {
        return new FolderDTO(f.getId(), f.getName(), f.getParentId(), f.getSortOrder());
    }
}
