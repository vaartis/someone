#ifdef SOMEONE_EMSCRIPTEN
// C++20 compatibility
#include <type_traits>
namespace std {
template< class T >
using result_of_t = typename std::invoke_result<T>::type;
}
#endif

#include_next <sol/sol.hpp>
