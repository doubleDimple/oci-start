package com.doubledimple.dao.entity;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.Table;
import java.time.LocalDateTime;

@Data
@Entity
@Table(name = "cloud_ssh_folder")
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class CloudSshFolder {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** 文件夹名称 */
    @Column(nullable = false, length = 100)
    private String name;

    /** 父级文件夹ID，顶层为 null */
    @Column(name = "parent_id")
    private Long parentId;

    /** 排序用 */
    @Column(name = "sort_order", columnDefinition = "INT DEFAULT 0")
    private int sortOrder;

    /** 创建时间 */
    @Column(name = "created_at")
    private LocalDateTime createdAt;

    /** 更新时间 */
    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    /** 是否已删除（逻辑删除） */
    @Column(name = "deleted", nullable = false)
    private Boolean deleted = false;

}

