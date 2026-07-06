using Microsoft.AspNetCore.Mvc.Filters;

namespace TerakarsaApp.API.Authorization;

public class RequireModuleAttribute : Attribute, IAuthorizationFilter
{
    private readonly string _moduleCode;

    public RequireModuleAttribute(string moduleCode)
    {
        _moduleCode = moduleCode;
    }

    public void OnAuthorization(AuthorizationFilterContext context)
    {
        if (!context.HttpContext.User.HasClaim("module", _moduleCode))
        {
            context.Result = new Microsoft.AspNetCore.Mvc.ForbidResult();
        }
    }
}
