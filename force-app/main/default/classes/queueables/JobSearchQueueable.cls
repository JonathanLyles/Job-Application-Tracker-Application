/**
 * Queueable Job: Asynchronous Job Search Processing
 * ================================================
 *
 * This queueable class handles asynchronous job search operations, allowing
 * the system to process multiple job board API calls without blocking the
 * user interface.
 */
public with sharing class JobSearchQueueable implements Queueable, Database.AllowsCallouts {
  private JobSearchCriteria criteria;
  private String requestId;

  /**
   * Constructor for queueable job search
   * @param criteria Search parameters
   * @param requestId Unique identifier for tracking this request
   */
  public JobSearchQueueable(JobSearchCriteria criteria, String requestId) {
    this.criteria = criteria;
    this.requestId = requestId;
  }

  /**
   * Execute the asynchronous job search
   * @param context Queueable context
   */
  public void execute(QueueableContext context) {
    try {
      // Get available strategies for selected boards
      List<IJobBoardSearchStrategy> strategies = JobBoardStrategyRegistry.createStrategies(
        criteria.selectedBoards
      );
      List<JobApplicationDomain> allResults = new List<JobApplicationDomain>();

      // Execute search across all selected job boards
      for (IJobBoardSearchStrategy strategy : strategies) {
        if (strategy.isValidCriteria(criteria)) {
          List<JobApplicationDomain> results = strategy.searchJobs(criteria);
          if (results != null) {
            allResults.addAll(results);
          }
        }
      }

      // Filter valid results
      List<JobApplicationDomain> validResults = new List<JobApplicationDomain>();
      for (JobApplicationDomain job : allResults) {
        if (job.isValid()) {
          validResults.add(job);
        }
      }

      // Store results (implementation would depend on storage mechanism)
      // For now, we'll use debug logs
      System.debug('Job search completed for request: ' + requestId);
      System.debug('Found ' + validResults.size() + ' valid job postings');
    } catch (Exception e) {
      System.debug('Error in job search queueable: ' + e.getMessage());
      // Error handling logic here
    }
  }
}
