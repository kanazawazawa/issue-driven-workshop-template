using Azure.Data.Tables;
using Azure.Identity;
using IssueDrivenWorkshop.Components;
using IssueDrivenWorkshop.Services;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents();

// Azure Table Storage の設定
var connectionString = builder.Configuration.GetValue<string>("AzureTableStorage:ConnectionString")
    ?? Environment.GetEnvironmentVariable("AZURE_TABLESTORAGE_CONNECTIONSTRING");
var storageAccountName = builder.Configuration.GetValue<string>("AzureTableStorage:StorageAccountName")
    ?? Environment.GetEnvironmentVariable("AZURE_TABLESTORAGE_STORAGEACCOUNTNAME");
var tableName = builder.Configuration.GetValue<string>("AzureTableStorage:TableName")
    ?? Environment.GetEnvironmentVariable("AZURE_TABLESTORAGE_TABLENAME")
    ?? "Expenses";

// 接続文字列があればそれを使用（ローカル開発向け）、なければ Managed Identity（Azure 向け）
TableServiceClient tableServiceClient;
if (!string.IsNullOrEmpty(connectionString))
{
    tableServiceClient = new TableServiceClient(connectionString);
}
else if (!string.IsNullOrEmpty(storageAccountName))
{
    var endpoint = new Uri($"https://{storageAccountName}.table.core.windows.net");
    tableServiceClient = new TableServiceClient(endpoint, new DefaultAzureCredential());
}
else
{
    throw new InvalidOperationException(
        "Azure Table Storage is not configured. " +
        "Set 'AzureTableStorage:ConnectionString' (local dev) or " +
        "'AzureTableStorage:StorageAccountName' (Azure with Managed Identity).");
}

builder.Services.AddSingleton(new ExpenseRequestService(tableServiceClient, tableName));

var app = builder.Build();

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
    app.UseHsts();
}

app.UseHttpsRedirection();

app.UseStaticFiles();
app.UseAntiforgery();

app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode();

app.Run();
