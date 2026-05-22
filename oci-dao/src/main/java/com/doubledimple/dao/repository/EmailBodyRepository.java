package com.doubledimple.dao.repository;


import com.doubledimple.dao.entity.EmailBody;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.stereotype.Repository;

import java.util.List;


@Repository
public interface EmailBodyRepository extends JpaRepository<EmailBody, Long>, JpaSpecificationExecutor<EmailBody> {


    EmailBody findByEmailBodyId(String emailBodyId);

    void deleteByTenantEmailConfigId(Long tenantEmailConfigId);

    List<EmailBody> findByTenantEmailConfigId(Long tenantEmailConfigId);

    void deleteByEmailBodyId(String emailBodyId);
}
