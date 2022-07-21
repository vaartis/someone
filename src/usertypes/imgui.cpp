#include "imgui.h"
#include "misc/cpp/imgui_stdlib.h"

#include <numeric>
#include <sol/sol.hpp>

#include "usertypes.hpp"

#include "SFML/System/Vector2.hpp"
#include "SFML/Graphics/Color.hpp"

void register_imgui_usertypes(sol::state &lua) {
    lua["ImGui"] = lua.create_table_with(
        "Begin", [](const char *label) {
            return ImGui::Begin(label, nullptr, ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoCollapse);
        },
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
            int int_ptr = num;
            ImGui::InputInt(label, &int_ptr);
            return int_ptr;
        },
        "InputInt2", [](const char *label, std::array<int, 2> num) {
            ImGui::InputInt2(label, num.data()); return sol::as_table(num);
        },
        "InputInt4", [](const char *label, std::array<int, 4> num) {
            ImGui::InputInt4(label, num.data()); return sol::as_table(num);
        },
        "InputFloat", [](const char *label, float num) {
            float float_ptr = num;
            ImGui::InputFloat(label, &float_ptr);
            return float_ptr;
        },

        "Checkbox", [](const char *label, bool value) {
            auto changed = ImGui::Checkbox(label, &value);
            return std::make_pair(value, changed);
        },
        "Button", [](const char *text) { return ImGui::Button(text); },
        "RadioButton", sol::resolve<bool(const char*, bool)>(&ImGui::RadioButton),
        "Text", &ImGui::Text,
        "TextWrapped", &ImGui::TextWrapped,

        "BeginGroup", &ImGui::BeginGroup,
        "EndGroup", &ImGui::EndGroup,

        "SameLine", sol::overload(
            []() { ImGui::SameLine(); },
            [](float offset, float spacing) { ImGui::SameLine(offset, spacing); }
        ),

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
        "BeginMenu", &ImGui::BeginMenu,
        "EndMenu", &ImGui::EndMenu,

        "OpenPopup", [](const char *id) { return ImGui::OpenPopup(id); },
        "BeginPopupModal", [](const char *label) { return ImGui::BeginPopupModal(
                label, nullptr, ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoCollapse
            );
        },
        "BeginPopup", [](const char *label) { return ImGui::BeginPopup(
                label, ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoCollapse
            );
        },
        "EndPopup", ImGui::EndPopup,
        "CloseCurrentPopup", ImGui::CloseCurrentPopup,

        "BeginChild", [](const char* str_id, const sf::Vector2f &size) {
            return ImGui::BeginChild(str_id, ImVec2(size.x, size.y), true);
        },
        "EndChild", &ImGui::EndChild,

        "AddLine", [](sf::Vector2f a, sf::Vector2f b, sf::Color color, float thickness) {
            auto draw_list = ImGui::GetBackgroundDrawList();
            draw_list->AddLine(
                ImVec2(a.x, a.y),
                ImVec2(b.x, b.y),
                IM_COL32(color.r, color.g, color.b, color.a),
                thickness
            );
        },

        "BeginTabBar", &ImGui::BeginTabBar,
        "EndTabBar", &ImGui::EndTabBar,
        "BeginTabItem", [](const char *label) {
            return ImGui::BeginTabItem(label);
        },
        "EndTabItem", &ImGui::EndTabItem,

        "SetNextItemWidth", &ImGui::SetNextItemWidth
    );
    lua.new_enum(
        "ImGuiInputTextFlags",
        "None", ImGuiInputTextFlags_None,
        "EnterReturnsTrue", ImGuiInputTextFlags_EnterReturnsTrue,
        "ReadOnly", ImGuiInputTextFlags_ReadOnly
    );
    lua.new_enum(
        "ImGuiTabBarFlags",
        "None", ImGuiTabBarFlags_None
    );
    lua.new_enum(
        "ImGuiMouseButton",
        "Left", ImGuiMouseButton_Left,
        "Right", ImGuiMouseButton_Right,
        "Middle", ImGuiMouseButton_Middle
    );
}
