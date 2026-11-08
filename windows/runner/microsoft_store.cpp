#include "microsoft_store.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <appmodel.h>
#include <shobjidl.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Services.Store.h>
#include <map>
#include <string>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using List = flutter::EncodableList;
using Result = flutter::MethodResult<Value>;
using namespace winrt::Windows::Services::Store;

std::string StringArg(const Map& args, const char* key) {
  const auto it = args.find(Value(key));
  if (it == args.end()) return {};
  const auto value = std::get_if<std::string>(&it->second);
  return value ? *value : std::string{};
}
bool HasPackageIdentity() {
  UINT32 length = 0;
  return GetCurrentPackageFullName(&length, nullptr) == ERROR_INSUFFICIENT_BUFFER;
}
}

struct MicrosoftStoreBridge::State : std::enable_shared_from_this<State> {
  HWND window;
  bool alive = true;
  bool busy = false;
  StoreContext context{nullptr};
  std::map<std::string, StoreProduct> products;
  std::unique_ptr<flutter::MethodChannel<Value>> channel;

  static winrt::fire_and_forget Call(std::shared_ptr<State> state,
      std::string method, Map args, std::shared_ptr<Result> result) {
    // Keep completion on the Flutter platform thread. Outstanding operations
    // must not reply through a destroyed engine/window.
    winrt::apartment_context ui;
    Value reply;
    bool failed = false;
    try {
      if (!state->context) {
        state->context = StoreContext::GetDefault();
        winrt::check_hresult(state->context.as<IInitializeWithWindow>()->Initialize(state->window));
      }
      if (method == "products") {
        const auto monthly = StringArg(args, "monthlyId");
        const auto annual = StringArg(args, "annualId");
        if (monthly.size() != 12 || annual.size() != 12 || monthly == annual) {
          throw winrt::hresult_invalid_argument();
        }
        const auto found = co_await state->context.GetStoreProductsAsync(
            {L"Durable"}, {winrt::to_hstring(monthly), winrt::to_hstring(annual)});
        winrt::check_hresult(found.ExtendedError());
        List list;
        state->products.clear();
        for (const auto& pair : found.Products()) {
          const auto product = pair.Value();
          const auto id = winrt::to_string(product.StoreId());
          if (id != monthly && id != annual) continue;
          bool valid = false;
          bool hasTrial = false;
          for (const auto& sku : product.Skus()) {
            if (!sku.IsSubscription()) continue;
            const auto info = sku.SubscriptionInfo();
            // Ripot already supplies its account trial; no second Store trial.
            hasTrial = hasTrial || info.HasTrialPeriod();
            valid = valid || (info.BillingPeriod() == 1 &&
                info.BillingPeriodUnit() == (id == monthly ? StoreDurationUnit::Month : StoreDurationUnit::Year));
          }
          if (!valid || hasTrial) continue;
          state->products.insert_or_assign(id, product);
          list.emplace_back(Map{
              {Value("id"), Value(id)},
              {Value("title"), Value(winrt::to_string(product.Title()))},
              {Value("price"), Value(winrt::to_string(product.Price().FormattedPrice()))},
              {Value("owned"), Value(product.IsInUserCollection())},
              {Value("period"), Value(id == monthly ? "month" : "year")}});
        }
        reply = Value(list);
      } else if (method == "purchase") {
        const auto id = StringArg(args, "id");
        const auto item = state->products.find(id);
        if (item == state->products.end()) throw winrt::hresult_invalid_argument();
        const auto purchase = co_await item->second.RequestPurchaseAsync();
        std::string status;
        switch (purchase.Status()) {
          case StorePurchaseStatus::Succeeded: status = "purchased"; break;
          case StorePurchaseStatus::AlreadyPurchased: status = "owned"; break;
          case StorePurchaseStatus::NotPurchased: status = "cancelled"; break;
          case StorePurchaseStatus::NetworkError: status = "network-error"; break;
          default: status = "error"; break;
        }
        // This status is only a receipt prompt result, never an entitlement.
        reply = Value(status);
      } else if (method == "purchaseKey") {
        const auto ticket = StringArg(args, "serviceTicket");
        const auto uid = StringArg(args, "publisherUserId");
        if (ticket.empty() || ticket.size() > 24000 || uid.empty() || uid.size() > 128) {
          throw winrt::hresult_invalid_argument();
        }
        const auto key = co_await state->context.GetCustomerPurchaseIdAsync(
            winrt::to_hstring(ticket), winrt::to_hstring(uid));
        reply = Value(winrt::to_string(key));
      } else {
        co_await ui;
        if (state->alive) result->NotImplemented();
        state->busy = false;
        co_return;
      }
    } catch (...) {
      failed = true;
    }
    if (!state->alive) co_return;
    try { co_await ui; } catch (...) { co_return; }
    if (state->alive) {
      if (failed) result->Error("store-unavailable", "Microsoft Store could not complete this request.");
      else result->Success(reply);
    }
    state->busy = false;
  }
};

MicrosoftStoreBridge::MicrosoftStoreBridge(flutter::BinaryMessenger* messenger, HWND window)
    : state_(std::make_shared<State>()) {
  state_->window = window;
  state_->channel = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "ripot/microsoft_store", &flutter::StandardMethodCodec::GetInstance());
  std::weak_ptr<State> weak = state_;
  state_->channel->SetMethodCallHandler([weak](const auto& call, std::unique_ptr<Result> result) {
    const auto state = weak.lock();
    if (!state || !state->alive) return;
    if (!HasPackageIdentity()) {
      result->Error("not-packaged", "Install Ripot from Microsoft Store to make purchases.");
      return;
    }
    if (state->busy) { result->Error("busy", "A Microsoft Store request is already open."); return; }
    const auto args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
    if (!args) { result->Error("invalid-argument", "Store arguments are required."); return; }
    state->busy = true;
    State::Call(state, call.method_name(), *args, std::shared_ptr<Result>(std::move(result)));
  });
}

MicrosoftStoreBridge::~MicrosoftStoreBridge() {
  state_->alive = false;
  state_->channel->SetMethodCallHandler(nullptr);
  state_->channel.reset();
}
