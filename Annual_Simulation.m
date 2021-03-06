clear all
clc

%Select fluid of ejector cooling cycle
ECCfluid='R134a';
ECCPROP='COOLPROP';
%Select fluid of solar collectors
HTF='INCOMP::TVP1';
HTFPROP='COOLPROP';

%Reference Temperature (Celcius)
T_ref_c=80;
T_ref=273.15+T_ref_c;
%Reference Pressure (bar)
p_ref=4;

%Density of the HTF
d=DENSTP(T_ref,p_ref,HTF,HTFPROP);
%Cp of the HTF constant for Refrence Tempperature and Pressure
cp_htf=CPPT(p_ref,T_ref,HTF,HTFPROP);
%Cooling and Solar Data
run cooling_and_solar_data
%Demand in W
Q_cool=Q_cool_family.*10^3;
%Timestep
timestep=3600;
%Collectors modeling coefficients
a=0.80;
b=3.02;
c=0.0113;
% Storage tank heat loss coefficient(W/m2K)
U_L=0.5;
% Storage Tank Zones Number
n=20;
%Storage Tank Maximum Temperature (Celcius)
T_st_max=150;
%Fixed Temperature drop of exchnager
DT_htf_gen=20;

PP_gen_min=1;
% Design temperature of working fluid at generator outlet
DT_sh_evap=2;
DT_sh_gen=5;
DT_sc=5;
T_evap_sat_c=8;
T_gen_out_c_des=85;
T_gen_out_des=T_gen_out_c_des+273.15;
% Design condensation temperature of working fluid
T_cond_sat_c_des=30;
% Design cooling load calculated as a percentage of maximum
Q_cool_coef=0.1;
Q_cool_des_i=max(max(Q_cool))*Q_cool_coef/10^3;
Q_cool_des(month)=Q_cool_des_i;
Q_cool_dif=@(m_p)abs(Q_cool_des_i-f_ejector_sizing_ideal_simple_2022(ECCfluid,ECCPROP,m_p,T_gen_out_c_des,DT_sh_gen,T_cond_sat_c_des,DT_sc,T_evap_sat_c,DT_sh_evap));
options = optimoptions('fsolve','StepTolerance',0.001);
m_p=fsolve(Q_cool_dif,0.1,options);

% After finding the design primary flow rate we can calculate the geometry
% of the ejector at the design point and other performance and design data
[Q_evap,Q_cond,Q_sc,Q_gen,P_el_pump,COP_th,COP_tot,...
    er,m_p,m_s,m_tot,...
    p_gen_des,h_gen_in,T_gen_in,h_gen_out,T_gen_out,...
    p_evap,h_evap_in,T_evap_in,h_evap_out,T_evap_out,...
    p_cond,h_cond_in,T_cond_in,h_cond_out,T_cond_out,...
    h_sc_out,T_sc_out,...
    A_ratio,D_t,A_t,D_p_1,A_p_1,D_3,A_3,dif_p,p_c_des,T_crit,T_p_c] = f_ejector_sizing_ideal_simple_2022(ECCfluid,ECCPROP,m_p,T_gen_out_c_des,DT_sh_gen,T_cond_sat_c_des,DT_sc,T_evap_sat_c,DT_sh_evap);

Acol_i=80;
Dst_i=0.5;
Hst_i=1.5;
Vst=pi*(Dst_i/2)^2*Hst_i;
%Storage Tank Mass (kg)
M_st=d*Vst;
% Storage Tank Zones Surface (m^2)
for i=1:n
    A_st(i)=pi*Dst_i*Hst_i/n;
end
for month=1:12
    display(month)
    if sum(Q_cool(:,month))<=0
        for t=1:24
            P_el_pump(t)=0;
            Q_sup(t)=0;
            Q_col(t)=0;
            Q_col_max(t)=0;
            Q_cool_sup(t)=0;
            Q_sup_useful(t)=0;
            Q_cool(t,month)=0;
            T_condenser_matrix(t,month)=0;
        end
    else
        status_month(month)=0;
        while status_month(month)==0
            % First Initialization of Tes Temperature
            T_st(1,1)=T_amb(1)+50;
            T_st(1,n)=T_amb(1)+42;
            step= (40-32)/n;
            for i=1:n-1
                T_st(1,i+1)=T_st(1,i)-step;
            end
            Mean_tes_temperature(1)=mean(T_st(1,:));
            %Joule
            Q_tes(1)=sum(M_st/n*cp_htf*(T_st(1,:)))/10000;
            for i=1:n
                dQ_loss(1,i)=U_L*A_st(i)*(T_st(1,i)-T_amb(1));
            end
            Q_loss(1)=sum(dQ_loss(1,:));
            
            Q_col(1)=0;
            %ECC
            P_el_pump(1)=0;
            %Towards ECC closed subcircuit
            T_threshold(1)=0;
            m_htf(1)=0;
            T_htf_gen_in(1)=T_st(1,1);
            T_htf_gen_out(1)=T_htf_gen_in(1)-DT_htf_gen;
            %Collectors circuit
            m_col(1)=0;
            T_col_in(1)=T_st(1,n);
            T_col_out(1)=T_col_in(1);            
            %
            Q_col(1)=m_col(1)*(T_col_out(1)-T_col_in(1));
            Q_sup(1)=m_htf(1)*(T_htf_gen_in(1)-T_htf_gen_out(1));          
                      
            %Next Hour
            T_col_in(2)=T_st(1,n);
            T_htf_gen_in(2)=T_st(1,1);
            Q_tes(2)=Q_tes(1)-Q_loss(1);
            for t=2:24
                %disp(t)
                cp_htf=CPPT(p_ref,Mean_tes_temperature(t-1)+273.15,HTF,HTFPROP);
                %Our Tes Modeling every Timestep has 4 inputs
                %m_col,m_htf,T_col_out,T_ecc_out and calculates 2 outputs
                %T_col_in(t+1), T_htf_gen_in(t+1). In order to see whetether we can
                %provide energy to the ECC we have to check 4 conditions :If we
                %have Q_demand,if the PP>1,if T_ecc_out>T_st_min and if Q_tes is
                %enough                
                % The condensation saturation temperature is calculated by assuming that it is 20 K
                % above the ambient temperature
                T_cond_sat_c_i=T_amb(t,month)+10;
                %T_cond_sat(t)=T_cond_sat_c_i+20;
                T_cond_sat_i=T_cond_sat_c_i+273.15;              

                if Q_cool(t,month)>0                   
                    
                    dif_p=@(p_gen)abs(f_ejector_off_design(ECCfluid,ECCPROP,p_gen,T_cond_sat_c_i,D_t,A_t,D_p_1,A_p_1,D_3,A_3)-0.01);
                    options = optimoptions('fmincon','Display','off','Algorithm','interior-point','TolFun',0.001,'TolX',0.001);
                    nonlcon=[];
                    p_gen_i=fmincon(dif_p,p_gen_des,[],[],[],[],p_c_des+1,p_gen_des,nonlcon,options);
                    p_gen1(i)=p_gen_i;
                    [dif_p_i,COP_ecc_i,COP_ecc_th_i,Q_evap_ecc_i_th,Q_gen_ecc_i,er_i,m_p_i,m_s_i,p_gen_i,T_gen_out_c_i,T_gen_in_c_i,p_c_i,P_el_pump,T_c_sat_c] = f_ejector_off_design(ECCfluid,ECCPROP,p_gen_i,T_cond_sat_c_i,D_t,A_t,D_p_1,A_p_1,D_3,A_3);
                    
                    T_condenser_matrix(t,month)=T_c_sat_c;

                    COP_ecc_i(t)=COP_ecc_i;
                    P_el_pump(t)=P_el_pump;
                    T_gen_out_i=T_gen_out_c_i+273.15;
                    T_gen_in_i=T_gen_in_c_i+273.15;
                    h_gen_out_i=HPT(p_gen_i,T_gen_out_i,ECCfluid,ECCPROP);
                    h_gen_in_i=HPT(p_gen_i,T_gen_in_i,ECCfluid,ECCPROP);
                    
                    % The primary flow temperature is T_gen_out_c_i. Furthermore, the heat input that must be supplied to the generator
                    % is Q_gen_ecc_th. This heat input is necessary for the ECC to operate at this timestep. Therefore we need to check two things:
                    % 1) that the temperature in the solar tank is sufficiently high and 2) that the heat stored in the tank is sufficiently high
                    
                    %  Heat demand at time step
                    %Q_d_i=Q_gen_ecc_i/n_ex;
                    Q_d_i=Q_gen_ecc_i;
                    Q_d(t)=Q_d_i*10^3;
                    
                    %We now will calculate T_htf_gen_out and m_htf
                    %Mass of heat transfer fluid calculation
                    if T_htf_gen_in(1)<32.01
                        T_htf_gen_in(1)=32.01;
                    end
                    T_htf_gen_in_i=T_htf_gen_in(t);
                    T_htf_gen_out(t)=T_htf_gen_in(t)-DT_htf_gen;
                    T_htf_gen_out_i=T_htf_gen_out(t);
                    h_htf_gen_in_i=HPT(p_ref,T_htf_gen_in_i+273.15,HTF,HTFPROP);
                    h_htf_gen_out_i=HPT(p_ref,T_htf_gen_out_i+273.15,HTF,HTFPROP);
                    m_htf_i=Q_gen_ecc_i/(h_htf_gen_in_i-h_htf_gen_out_i);
                    m_htf_ii(t)=m_htf_i;
                    m_htf(t)=m_htf_i;
                    
                    % First condition check (temperature of storage tank sufficiently high)
                    % Now we calculate the pinch point in the generator under these assumptions
                    PP_gen=fMITA(50,ECCfluid,ECCPROP,m_p_i,p_gen_i,T_gen_in_i,T_gen_out_i,h_gen_in_i,h_gen_out_i,...
                        HTF,HTFPROP,m_htf_i,p_ref,T_htf_gen_in_i+273,T_htf_gen_out_i,h_htf_gen_in_i,h_htf_gen_out_i);
                    %if PP_gen<-80
                    %vvv=[m_p_i,p_gen_i,T_gen_in_i,T_gen_out_i,h_gen_in_i,h_gen_out_i,m_htf_i,p_ref,T_htf_gen_in_i+273.15,T_htf_gen_out_i+273.15,h_htf_gen_in_i,h_htf_gen_out_i]
                    %end
                    PPgen(t)=PP_gen;
                    
                    % Then we calculate the minimum storage tank temperature that is required for having a pinch point higher than the minimum given the
                    % operating conditions of the ECC at this timestep (this is necessary to define the stored energy in the storage tank which can be utilized)
                    dif_PP_gen=@(T_htf_in_search)abs(PP_heater_search(50,ECCfluid,ECCPROP,m_p_i,p_gen_i,T_gen_in_i,T_gen_out_i,h_gen_in_i,h_gen_out_i,...
                        HTF,HTFPROP,p_ref,T_htf_in_search,DT_htf_gen)-PP_gen_min);
                    options_PP_gen = optimoptions('fsolve','Display','off','StepTolerance',0.1);
                    T_threshold(t)=fsolve(dif_PP_gen,T_gen_out_i+10,options_PP_gen)-273.15;
                    
                    %We will calculate m_col and T_col_out for each timestep
                    %No Existing Solar Radiation
                else Q_d(t)=0;
                    PPgen(t)=0;
                    T_htf_gen_out(t)=0;
                    m_htf(t)=0;
                    T_threshold(t)=0;
                    COP_ecc_i(t)=0;
                    
                end
                if Gb_rad(t,month)<=0.1
                    %We disconect the collectors in this timestep.Thus the flow of the heat trasnfer
                    %fluid is equal to zero. However we need an input for T_col_out
                    %in order to modelize the TES. This input plays no role becouse
                    %it is multiplied with m_col thus zero.
                    ncol(t)=0;
                    T_col_out(t)=T_col_in(t);
                    m_col(t)=0;
                else
                    %Existing Solar Radiation
                    %Loop for calculating output temperature from the collectors
                    %Initialaziation of output temperature from the collectors
                    T_col_out(t)=T_col_in(t);
                    status_col=0;
                    m_col(t)=1;
                    while status_col==0
                        Tcol(t)=(T_col_in(t)+T_col_out(t))/2;
                        if Tcol(t)<13
                            Tcol(t)=13;
                        end
                        cp_htf=CPPT(p_ref,Tcol(t)+273.15,HTF,HTFPROP);
                        Tcol(t)=(T_col_in(t)+T_col_out(t))/2;
                        ncol(t)=a-b*(Tcol(t)-T_amb(t,month))/(Gb_rad(t,month))-c*((Tcol(t)-T_amb(t,month)^2)/(Gb_rad(t,month)));
                        Q_col_max(t)=ncol(t)*Acol_i.*Gb_rad(t,month);
                        T_out_new(t)=(Q_col_max(t)/(m_col(t)*cp_htf) + T_col_in(t));
                        s(t)=abs((T_out_new(t)-T_col_out(t))/T_col_out(t));
                        if s(t)<0.01
                            status_col=1;
                        else
                            T_col_out(t)=T_out_new(t);
                        end
                    end
                    %Calculated output temperature from the collectors
                    T_col_out(t)=T_out_new(t);
                end
                T1221312(t,month)=T_col_out(t);
                if ncol(t)<=0
                    m_col(t)=0;
                    T_col_out(t)=0;
                end
                %We now can chech whether our conditions are met
                if Q_d(t)<10 ||  PP_gen<1 || T_htf_gen_in(t)<T_threshold(t) || COP_ecc_i(t)<=0 
                    if COP_ecc_i(t)<=0
                        MATRIX(t,month)=1;
                    end
                    COP_ecc_i(t)=0;
                    %HTF circuit closed
                    m_htf(t)=0;
                    run 'TES_modeling_script'
                else
                    %m_htf exei oristei
                    m_htf(t)=m_htf_i;
                    run 'TES_modeling_script'
                    %disp('0')
                    if T_st(t,1)<T_threshold(t)
                        status_TES=0;
                        %l=0;
                        m_htf(t)=0.01;
                        while status_TES==0 && m_htf(t)<m_htf_i
                            
                            run 'TES_modeling_script'
                            %disp(T_st(t,1))
                            if T_st(t,1)<T_threshold(t)+1
                                status_TES=1;
                            else
                                m_htf(t)=m_htf(t)+0.01;
                                %l=l+1
                            end
                            m_htf_max(t)=m_htf(t);
                            mm=m_htf(t);
                            %disp(mm)
                            Q_sup_max(t)=m_htf_max(t)*cp_htf*20;
                            if Q_sup_max(t)>Q_d(t)
                                m_htf(t)=m_htf_i;
                                run TES_modeling_script
                            else
                                m_htf(t)=m_htf_max(t);
                                %disp(m_htf(t))
                            end
                        end
                    else
                        dif_m(t)=m_htf(t)-m_htf_ii(t);
                        %if dif_m(t)==0
                        %disp('goooooooood')
                        %end
                        m_htf(t)=m_htf_i;
                        run TES_modeling_script
                    end
                    if m_htf(t)<0.01
                        %disp('TOO LOW MASS')
                        %disp(t)
                        m_htf(t)=0;
                        run TES_modeling_script
                    end
                end
                if Q_d(t)>0.1
                    %Energy supplied to the
                    %Exchanger/Generator
                    Q_sup(t)=m_htf(t)*(h_htf_gen_in_i-h_htf_gen_out_i)*10^3;
                    
                    %Cooling that can be produced based
                    %on the heat input
                    Q_cool_sup(t)=Q_sup(t)*COP_ecc_i(t);
                    
                    if Q_cool_sup(t)>Q_cool(t,month)
                        Q_cool_sup(t)=Q_cool(t,month);
                    end
                    if COP_ecc_i(t)>0
                        Q_sup_useful(t)=Q_cool_sup(t)/COP_ecc_i(t);
                    end
                else
                    Q_sup(t)=0;
                    Q_cool_sup(t)=0;
                    Q_sup_useful(t)=0;
                    
                end
                
                Q_loss(t)=sum(dQ_loss(t,:));
                Q_col(t)=m_col(t)*cp_htf*(T_col_out(t)-T_col_in(t));
                T_col_in(t+1)=T_st(t,n);
                T_htf_gen_in(t+1)=T_st(t,1);
                Q_tes(t+1)=Q_tes(t)+Q_col(t)-Q_sup(t)-Q_loss(t);
                
                Mean_tes_temperature(t)=mean(T_st(t,:));
                if Mean_tes_temperature(t)<13
                    Mean_tes_temperature(t)=13;
                end
                COP_ECC(t,month)= COP_ecc_i(t);
                T_HTF_GEN_IN(t,month)=T_htf_gen_in(t);
                Q_COOL_SUP(t,month)=Q_cool_sup(t);
                T_THRESHOLD(t,month)=T_threshold(t);
                
            end
            error_day=abs(T_st(25)-T_st(1));
            if error_day<1
                status_month(month)=1;
            else
                T_st(1)=T_st(25);
            end

        end
    end
    
    
    E_el_pump_month(month)=sum(P_el_pump(:))*timestep*days(month)*10^3;
    %Energy supplied to the exchanger from the hot
    %current
    E_sup_month(month)=sum(Q_sup(:))*timestep*days(month);
    %Generator demand energy
    %E_d(month)=sum(Q_d(:))*timestep*days(month);
    %Losses from TES system
    %E_loss(month)=sum(Q_loss(:))*timestep*days(month);
    E_sol_month(month)=sum(Gb_rad(:,month))*Acol_i*timestep*days(month);
    E_col_month(month)=sum(Q_col(:))*timestep*days(month);
    E_col_max_month(month)=sum(Q_col_max(:))*timestep*days(month);
    E_cool_sup_month(month)=sum(Q_cool_sup(:))*timestep*days(month);
    E_sup_useful_month(month)=sum(Q_sup_useful(:))*timestep*days(month);
    E_cool_month(month)=sum(Q_cool(:,month))*timestep*days(month);
    E_el_pump_month_month(month)=sum(P_el_pump(:))*days(month);
    cool_frac_month_month(month)=E_cool_sup_month(month)/E_cool_month(month);
    if cool_frac_month_month(month)>1
        disp('error')
    end
    sol_use_frac_month_month(month)=E_col_month(month)/E_col_max_month(month);
    eta_sol_month_month(month)=E_sup_month(month)/E_sol_month(month);
    % hours_month(month)=nnz(Q_cool_sup(:,month))*days(month);
    
end
E_sol_year =sum(E_sol_month(:));
E_col_max_year =sum(E_col_max_month(:));
E_col_year =sum(E_col_month(:));
E_sup_year =sum(E_sup_month(:));
E_sup_useful_year =sum(E_sup_useful_month(:));
E_cool_sup_year =sum(E_cool_sup_month(:));
E_el_pump_year =sum(E_el_pump_month(:));
E_cool_year =sum(E_cool_month(:));
%hours_year(kk,jj,ii,m,l,k)=sum(hours_month(:));

% contribution to cooling load
cool_frac_year =E_cool_sup_year /E_cool_year  ;
sol_use_frac_year =E_col_year /E_col_max_year  ;
eta_sol_year =E_sup_useful_year  /E_sol_year  ;


eta_cool_year  =E_cool_sup_year  /E_sol_year  ;
%enddd=1

