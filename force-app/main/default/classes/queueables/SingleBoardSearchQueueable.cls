/**
 * @description Executes search against a single job board. This is the core execution
 *              unit that performs HTTP callouts, parses responses, and persists results.
 *              Used both independently for single-board searches and as child queueables
 *              in composite fan-out scenarios.
 * @author Jonathan Lyles
 * @date 2026-01-03
 */
public class SingleBoardSearchQueueable implements Queueable, Database.AllowsCallouts {
  private String searchId;
  private JobSearchCriteria criteria;
  private String jobBoard;
  private Boolean isCompositeChild;

  /**
   * @description Constructor for single board search queueable (PMD compliant - 3 parameters)
   * @param searchId Unique identifier for the search
   * @param criteria Search criteria object
   * @param jobBoard Name of the job board to search
   */
  public SingleBoardSearchQueueable(
    String searchId,
    JobSearchCriteria criteria,
    String jobBoard
  ) {
    this.searchId = searchId;
    this.criteria = criteria;
    this.jobBoard = jobBoard;
    this.isCompositeChild = false; // Default for single board searches
  }

  /**
   * @description Alternative constructor for composite searches (PMD compliant - 3 parameters)
   * @param criteria Search criteria object
   * @param jobBoard Name of the job board to search
   * @param isCompositeChild Whether this is part of a composite search
   */
  public SingleBoardSearchQueueable(
    JobSearchCriteria criteria,
    String jobBoard,
    Boolean isCompositeChild
  ) {
    this.criteria = criteria;
    this.jobBoard = jobBoard;
    this.isCompositeChild = isCompositeChild;
    this.searchId = null; // Will be set during execution if needed
  }

  /**
   * @description Main execution method that performs the job search
   * @param context QueueableContext from Salesforce platform
   */
  public void execute(QueueableContext context) {
    System.debug(
      'SingleBoardSearchQueueable.execute() - searchId: ' +
        searchId +
        ', board: ' +
        jobBoard
    );

    String status = 'SUCCESS';
    String errorMessage = null;
    Integer totalResults = 0;

    try {
      // Resolve strategy for this job board
      IJobBoardSearchStrategy strategy = JobBoardStrategyRegistry.createStrategy(
        jobBoard
      );

      System.debug(
        'SingleBoardSearchQueueable.execute() - strategy resolved: ' + strategy
      );

      // Execute search via strategy
      List<JobApplicationDomain> results = strategy.searchJobs(criteria);
      totalResults = results != null ? results.size() : 0;

      System.debug(
        'SingleBoardSearchQueueable.execute() - found ' +
          totalResults +
          ' results'
      );

      // Persist results if any found
      if (totalResults > 0) {
        persistResults(results);
      }
    } catch (Exception e) {
      System.debug(
        'SingleBoardSearchQueueable.execute() - ERROR: ' + e.getMessage()
      );
      status = 'FAILURE';
      errorMessage = e.getMessage();
    }

    // Publish completion event (for single board) or notify tracking service (for composite)
    if (isCompositeChild) {
      // Notify tracking service for fan-in coordination
      notifyTrackingService(status, totalResults, errorMessage);
    } else {
      // Publish completion event directly for single board searches
      publishCompletionEvent(status, totalResults, errorMessage);
    }
  }

  /**
   * @description Persists job application results to Salesforce
   * @param results List of job applications to persist
   */
  private void persistResults(List<JobApplicationDomain> results) {
    List<Job_Application__c> recordsToInsert = new List<Job_Application__c>();

    for (JobApplicationDomain result : results) {
      recordsToInsert.add(result.toJobApplicationRecord());
    }

    if (!recordsToInsert.isEmpty()) {
      insert recordsToInsert;
      System.debug(
        'SingleBoardSearchQueueable.persistResults() - inserted ' +
          recordsToInsert.size() +
          ' records'
      );
    }
  }

  /**
   * @description Notifies tracking service of completion (used in composite searches)
   * @param status SUCCESS, PARTIAL_SUCCESS, or FAILURE
   * @param totalResults Number of results found
   * @param errorMessage Error details if applicable
   */
  private void notifyTrackingService(
    String status,
    Integer totalResults,
    String errorMessage
  ) {
    System.debug(
      'SingleBoardSearchQueueable.notifyTrackingService() - board: ' +
        jobBoard +
        ', status: ' +
        status
    );

    // Create completion data object
    JobSearchTrackingService.BoardCompletionData completionData;
    if (status == 'SUCCESS') {
      completionData = JobSearchTrackingService.createSuccessCompletion(
        jobBoard,
        totalResults
      );
    } else {
      completionData = JobSearchTrackingService.createFailureCompletion(
        jobBoard,
        errorMessage
      );
    }

    JobSearchTrackingService.notifyBoardCompletion(searchId, completionData);
  }

  /**
   * @description Publishes completion event for single board searches
   * @param status SUCCESS, PARTIAL_SUCCESS, or FAILURE
   * @param totalResults Number of results found
   * @param errorMessage Error details if applicable
   */
  private void publishCompletionEvent(
    String status,
    Integer totalResults,
    String errorMessage
  ) {
    JobSearchCompleted__e event = new JobSearchCompleted__e(
      SearchId__c = searchId,
      Status__c = status,
      JobBoardsProcessed__c = jobBoard,
      TotalResults__c = totalResults,
      ErrorMessage__c = errorMessage
    );

    EventBus.publish(event);
    System.debug(
      'SingleBoardSearchQueueable.publishCompletionEvent() - published event for searchId: ' +
      searchId
    );
  }

  /**
   * @description Custom exception for job search errors
   */
  public class JobSearchException extends Exception {
  }
}
