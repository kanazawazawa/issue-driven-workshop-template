using Azure.Data.Tables;
using IssueDrivenWorkshop.Models;

namespace IssueDrivenWorkshop.Services;

public class ExpenseRequestService
{
    private readonly TableClient _tableClient;
    
    // 業務ID（定数）
    private const string BusinessId = "expense-request";

    public ExpenseRequestService(string connectionString, string tableName)
    {
        var tableServiceClient = new TableServiceClient(connectionString);
        _tableClient = tableServiceClient.GetTableClient(tableName);
        _tableClient.CreateIfNotExists();
        
        // 初回のみテストデータを作成
        SeedInitialDataAsync().GetAwaiter().GetResult();
    }

    private async Task SeedInitialDataAsync()
    {
        // データが既に存在する場合は何もしない
        await foreach (var _ in _tableClient.QueryAsync<ExpenseRequest>(e => e.BusinessId == BusinessId, maxPerPage: 1))
        {
            return; // データがあれば終了
        }

        // テストデータを1件作成
        var testData = new ExpenseRequest
        {
            PartitionKey = BusinessId,
            RowKey = Guid.NewGuid().ToString(),
            BusinessId = BusinessId,
            ExpenseDate = new DateTime(2025, 1, 20, 0, 0, 0, DateTimeKind.Utc),
            EmployeeName = "鈴木一郎",
            Department = "営業部",
            Category = "会議費",
            Amount = 8500,
            Description = "顧客との打ち合わせ（ランチミーティング）",
            Status = "申請中"
        };

        await _tableClient.AddEntityAsync(testData);
    }

    public async Task<List<ExpenseRequest>> GetAllExpenseRequestsAsync()
    {
        var expenseRequests = new List<ExpenseRequest>();
        
        // 業務IDでフィルタリング
        await foreach (var entity in _tableClient.QueryAsync<ExpenseRequest>(e => e.BusinessId == BusinessId))
        {
            expenseRequests.Add(entity);
        }

        return expenseRequests.OrderByDescending(e => e.ExpenseDate).ToList();
    }

    public async Task<ExpenseRequest?> GetExpenseRequestAsync(string partitionKey, string rowKey)
    {
        try
        {
            var response = await _tableClient.GetEntityAsync<ExpenseRequest>(partitionKey, rowKey);
            return response.Value;
        }
        catch (Azure.RequestFailedException ex) when (ex.Status == 404)
        {
            return null;
        }
    }

    public async Task<ExpenseRequest> CreateExpenseRequestAsync(ExpenseRequest expenseRequest)
    {
        // PartitionKeyに業務IDを設定
        expenseRequest.PartitionKey = BusinessId;
        expenseRequest.BusinessId = BusinessId;
        
        if (string.IsNullOrEmpty(expenseRequest.RowKey))
        {
            expenseRequest.RowKey = Guid.NewGuid().ToString();
        }

        await _tableClient.AddEntityAsync(expenseRequest);
        return expenseRequest;
    }

    public async Task<ExpenseRequest> UpdateExpenseRequestAsync(ExpenseRequest expenseRequest)
    {
        await _tableClient.UpdateEntityAsync(expenseRequest, expenseRequest.ETag);
        return expenseRequest;
    }

    public async Task DeleteExpenseRequestAsync(string partitionKey, string rowKey)
    {
        await _tableClient.DeleteEntityAsync(partitionKey, rowKey);
    }
}
