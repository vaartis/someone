#include "imgui.h"
#include "misc/cpp/imgui_stdlib.h"

#include <sol/sol.hpp>

#include "usertypes.hpp"

void register_imgui_usertypes(sol::state &lua) {
    lua["ImGui"] = lua.create_table_with(
        "Begin", &ImGui::Begin,
        "End", &ImGui::End,

        "InputText", sol::overload(
            [](const char *label, std::string str) {
                bool submitted = ImGui::InputText(label, &str, ImGuiInputTextFlags_EnterReturnsTrue);
                return std::make_tuple(str, submitted);
            },
            [](const char *label, std::string str, ImGuiInputTextFlags_ flags) {
                bool changed = ImGui::InputText(label, &str, flags);
                return std::make_tuple(str, changed);
            }
        ),
        "InputInt", [](const char *label, int num) {
            ImGui::InputInt(label, &num); return num;
        },
        "InputInt2", [](const char *label, std::array<int, 2> num) {
            ImGui::InputInt2(label, num.data()); return sol::as_table(num);
        },
        "InputInt4", [](const char *label, std::array<int, 4> num) {
            ImGui::InputInt4(label, num.data()); return sol::as_table(num);
        },

        "Checkbox", [](const char *label, bool value) { ImGui::Checkbox(label, &value); return value; },
        "Button", [](const char *text) { return ImGui::Button(text); },
        "Text", &ImGui::Text,

        "BeginGroup", &ImGui::BeginGroup,
        "EndGroup", &ImGui::EndGroup,

        "SameLine", []() { ImGui::SameLine(); },

        "TreeNode", sol::resolve<bool(const char *)>(&ImGui::TreeNode),
        "TreePop", &ImGui::TreePop,

        "IsKeyDown", &ImGui::IsKeyDown,
        "IsMouseClicked", &ImGui::IsMouseClicked,
        "IsMouseDoubleClicked", &ImGui::IsMouseDoubleClicked,
        "IsMouseDown", &ImGui::IsMouseDown,
        "GetMousePos", [] { auto pos = ImGui::GetMousePos(); return sf::Vector2f(pos.x, pos.y); },
        "IsAnyWindowHovered", [] { return ImGui::IsWindowHovered(ImGuiHoveredFlags_AnyWindow); },
        "IsAnyItemHovered", &ImGui::IsAnyItemHovered,

        "BeginTooltip", &ImGui::BeginTooltip,
        "EndTooltip", &ImGui::EndTooltip,
        "SetTooltip", [](const char *str) { ImGui::SetTooltip("%s", str); },

        "Separator", &ImGui::Separator,
        "Spacing", &ImGui::Spacing,

        "BeginCombo", [](const char* label, const char* preview_value) { return ImGui::BeginCombo(label, preview_value); },
        "EndCombo", &ImGui::EndCombo,
        "Selectable", [](const char* label, bool selected = false) { return ImGui::Selectable(label, selected); },
        "ListBox", [](const char* label, int current_item, std::vector<const char *> items) {
            int curr_item_ptr = current_item;
            bool changed = ImGui::ListBox(label, &curr_item_ptr, items.data(), items.size());

            return std::make_tuple(curr_item_ptr, changed);
        },

        "OpenPopup", &ImGui::OpenPopup,
        "BeginPopupModal", [](const char *label) { return ImGui::BeginPopupModal(
                label, nullptr, ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoCollapse
            );
        },
        "BeginPopup", [](const char *label) { return ImGui::BeginPopup(
                label, ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoCollapse
            );
        },
        "EndPopup", ImGui::EndPopup,
        "CloseCurrentPopup", ImGui::CloseCurrentPopup
    );
    lua.new_enum(
        "ImGuiInputTextFlags",
        "None", ImGuiInputTextFlags_None,
        "EnterReturnsTrue", ImGuiInputTextFlags_EnterReturnsTrue
    );
    lua.new_enum(
        "ImGuiMouseButton",
        "Left", ImGuiMouseButton_Left,
        "Right", ImGuiMouseButton_Right,
        "Middle", ImGuiMouseButton_Middle
    );
}
