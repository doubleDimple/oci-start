package com.doubledimple.dao.repository;


import com.doubledimple.dao.entity.EmailSendRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.stereotype.Repository;


@Repository
public interface EmailSendRecordRepository extends JpaRepository<EmailSendRecord, Long>, JpaSpecificationExecutor<EmailSendRecord> {

    void deleteByEmailBodyId(String emailBodyId);

    EmailSendRecord findByEmailSendRecordId(String emailSendRecordId);

}
